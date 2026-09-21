#!/usr/bin/env python3
"""Deterministic typed Dart/Dio transport. Business objects and persisted commands stay separate."""
import copy,json,pathlib,re,subprocess,os
root=pathlib.Path(__file__).resolve().parents[1]
spec=json.loads((root/'contracts/openapi/biobalance.json').read_text())
out=root/'apps/mobile/lib/data/services/api/generated';out.mkdir(parents=True,exist_ok=True)
schemas=copy.deepcopy(spec['components']['schemas']);parents={}
def pascal(value):return ''.join(v[:1].upper()+v[1:] for v in re.split(r'[^A-Za-z0-9]+',value) if v)
def literal(value):return json.dumps(value,ensure_ascii=False).replace('$',r'\$')
def refname(s):return s['$ref'].split('/')[-1]
def nullable(s):return any(v.get('type')=='null' for v in s.get('anyOf',[])) or s.get('nullable',False)
def core(s):
 if nullable(s):
  variants=[v for v in s.get('anyOf',[]) if v.get('type')!='null']
  if len(variants)==1:return variants[0]
 return s

def hoist(schema,name,root_schema=False):
 s=copy.deepcopy(schema)
 if '$ref' in s:return s
 if nullable(s):
  inner=hoist(core(s),name,root_schema)
  return {'anyOf':[inner,{'type':'null'}]}
 variants=s.get('oneOf',s.get('anyOf'))
 if variants:
  types={v.get('type') for v in variants}
  if len(types)==1 and next(iter(types)) in ['string','integer','number','boolean']:
   return {'type':next(iter(types)),**({'enum':[v['const'] for v in variants]} if all('const' in v for v in variants) else {})}
  if not root_schema:
   schemas[name]=s
   return {'$ref':'#/components/schemas/'+name}
  key='oneOf' if 'oneOf' in s else 'anyOf';normalized=[]
  for i,v in enumerate(variants):
   discriminator=next((p['const'] for p in v.get('properties',{}).values() if 'const' in p),None)
   branch=name+pascal(str(discriminator) if discriminator is not None else str(i+1))
   if '$ref' in v:branch=refname(v)
   else:schemas[branch]=v
   parents.setdefault(branch,set()).add(name)
   normalized.append({'$ref':'#/components/schemas/'+branch})
  s[key]=normalized
 elif s.get('type')=='object' and 'properties' in s:
  if not root_schema:
   schemas[name]=s;return {'$ref':'#/components/schemas/'+name}
  s['properties']={k:hoist(v,name+pascal(k)) for k,v in s['properties'].items()}
 elif s.get('type')=='object' and isinstance(s.get('additionalProperties'),dict):
  s['additionalProperties']=hoist(s['additionalProperties'],name+'Value')
 elif s.get('type')=='array':s['items']=hoist(s['items'],name+'Item')
 return s
visited=set()
while pending:=[name for name in schemas if name not in visited]:
 for name in pending:
  visited.add(name)
  if name!='JsonValue':schemas[name]=hoist(schemas[name],name,True)

def resolve(s,seen=None):
 seen=seen or set()
 if '$ref' in s:
  n=refname(s)
  if n not in seen:return resolve(schemas[n],seen|{n})
 return s

def dtype(schema):
 s=core(schema)
 if '$ref' in s:
  n=refname(s);r=resolve(s)
  if r.get('type') in ['string','integer','number','boolean','array'] or (r.get('type')=='object' and 'properties' not in r):return dtype(r)
  return n+'Dto'
 if 'oneOf' in s or 'anyOf' in s:raise ValueError('Unhoisted union: '+str(s))
 return {'string':'String','integer':'int','number':'double','boolean':'bool','null':'Null','array':lambda:'List<'+dtype(s['items'])+('?' if nullable(s['items']) else '')+'>','object':lambda:'Map<String, '+dtype(s['additionalProperties'])+('?' if nullable(s['additionalProperties']) else '')+'>'}[s['type']]() if s['type'] in ['array','object'] else {'string':'String','integer':'int','number':'double','boolean':'bool','null':'Null'}[s['type']]

def decode(s,value):
 if nullable(s):return f'{value} == null ? null : '+decode(core(s),value)
 if '$ref' in s:
  name=refname(s);r=resolve(s)
  if name=='JsonValue':return f'JsonValueDto.fromJson({value})'
  if r.get('type') in ['string','integer','number','boolean','array'] or (r.get('type')=='object' and 'properties' not in r):return decode(r,value)
  if r.get('type')=='object':return f'{name}Dto.fromJson(Map<String, dynamic>.from({value} as Map))'
  return f'{name}Dto.fromJson({value})'
 kind=s.get('type')
 if kind=='array':return f'List.unmodifiable(({value} as List).map((item) => {decode(s["items"],"item")}))'
 if kind=='object':return f'Map.unmodifiable(({value} as Map).map((key, item) => MapEntry(key as String, {decode(s["additionalProperties"],"item")})))'
 if kind=='integer':return f'({value} as num).toInt()'
 if kind=='number':return f'({value} as num).toDouble()'
 return f'{value} as '+dtype(s)

def encode(s,value):
 if nullable(s):return f'{value} == null ? null : '+encode(core(s),value+'!')
 if '$ref' in s:
  r=resolve(s)
  if refname(s)=='JsonValue' or r.get('type')=='object' and 'properties' in r or 'oneOf' in r or 'anyOf' in r:return value+'.toJson()'
  return encode(r,value)
 if s.get('type')=='array':return f'{value}.map((item) => {encode(s["items"],"item")}).toList()'
 if s.get('type')=='object':return f'{value}.map((key, item) => MapEntry(key, {encode(s["additionalProperties"],"item")}))'
 return value

lines=['// GENERATED by scripts/generate-dart-client.py. Do not edit.',"import 'wire_validation.dart';",'']
for name,s in schemas.items():
 c=name+'Dto';interfaces=', '.join(p+'Dto' for p in sorted(parents.get(name,[])));implements=' implements '+interfaces if interfaces else ''
 if name=='JsonValue':
  lines+=['final class JsonValueDto {',' final Object? value;',' JsonValueDto.fromJson(Object? value):value=freezeJson(value);',' Object? toJson()=>value;','}'];continue
 if '$ref' in s or s.get('type')!='object' and 'oneOf' not in s and 'anyOf' not in s or s.get('type')=='object' and 'properties' not in s:
  if interfaces:raise ValueError('Primitive union subtype '+name)
  lines+=['typedef '+c+' = '+dtype(s)+';'];continue
 variants=s.get('oneOf',s.get('anyOf'))
 if variants:
  lines+=[f'sealed class {c}{implements} {{',f' const {c}();',f' factory {c}.fromJson(Object? json) {{']
  for v in variants:lines+=[f'  if(matchesWire(json, {literal(refname(v))})) return {refname(v)}Dto.fromJson(json'+(' as Map<String,dynamic>' if resolve(v).get('type')=='object' else '')+');']
  lines += [f"  throw const FormatException('Invalid {name} result');",' }',' Object? toJson();','}'];continue
 props=s.get('properties',{});required=s.get('required',[])
 lines+=[f'final class {c}{implements} {{',' final Set<String> _presentFields;', ' Set<String> get presentFields => _presentFields;']
 args=['Set<String> presentFields = const {}'];initializers=['_presentFields=Set.unmodifiable(presentFields)']
 for f,p in props.items():
  if 'const' in p:
   lines += [f' {dtype(p)} get {f} => {literal(p["const"])};'];continue
  typ=dtype(p)+('?' if f not in required or nullable(p) else '')
  lines += [f' final {typ} {f};']
  prefix='required ' if f in required else ''
  if core(p).get('type') in ['array','object'] and 'properties' not in core(p):
   args+=[prefix+typ+' '+f];initializer=('List' if core(p).get('type')=='array' else 'Map')+'.unmodifiable('+f+')'
   initializers+=[f+'='+ (f+' == null ? null : ' if f not in required or nullable(p) else '')+initializer]
  else:args += [prefix+'this.'+f]
 lines += [f' {c}({{{", ".join(args)}}}):'+', '.join(initializers)+';',f' factory {c}.fromJson(Map<String,dynamic> json)=>{c}(', '  presentFields:json.keys.toSet(),']
 for f,p in props.items():
  if 'const' in p:continue
  access="json["+literal(f)+"]";expr=decode(p,access)
  if f not in required and not nullable(p):expr=f'{access} == null ? null : '+expr
  lines += ['  '+f+': '+expr+',']
 lines += [' );',' Map<String,dynamic> toJson()=>{']
 for f,p in props.items():
  if 'const' in p:expr=literal(p['const'])
  elif f not in required and not nullable(p):expr=f'{f} == null ? null : '+encode(p,f+'!')
  else:expr=encode(p,f)
  lines+=['  '+(f'if({f} != null || _presentFields.contains({literal(f)})) ' if f not in required else '')+literal(f)+': '+expr+',']
 lines+=[' };','}']
(out/'models.dart').write_text('\n'.join(lines)+'\n')
validation='''// GENERATED schema matching for tagged wire unions; domain validation is separate.
Object? freezeJson(Object? value) {
 if(value is Map) return Map<String,Object?>.unmodifiable(value.map((k,v)=>MapEntry(k as String,freezeJson(v))));
 if(value is List) return List<Object?>.unmodifiable(value.map(freezeJson));
 if(value == null || value is String || value is bool || value is num) return value;
 throw const FormatException('Invalid JSON value');
}
bool matchesWire(Object? value,String name)=>_matches(value,_schemas[name]!);
bool _matches(Object? value,Map<String,dynamic> schema) {
 if(schema[r'$ref'] case final String ref) return matchesWire(value,ref.split('/').last);
 if(schema['const'] != null && value != schema['const']) return false;
 if(schema['enum'] case final List values) { if(!values.contains(value)) return false; }
 if(schema['oneOf'] case final List variants) return variants.where((s)=>_matches(value,Map<String,dynamic>.from(s))).length==1;
 if(schema['anyOf'] case final List variants) return variants.any((s)=>_matches(value,Map<String,dynamic>.from(s)));
 switch(schema['type']) {
  case 'null':return value == null;
  case 'string':return value is String;
  case 'integer':return value is int;
  case 'number':return value is num;
  case 'boolean':return value is bool;
  case 'array':return value is List && value.every((v)=>_matches(v,schema['items']));
  case 'object':
   if(value is! Map) return false;
   final properties=Map<String,dynamic>.from(schema['properties'] ?? {});
   if(!(schema['required'] as List? ?? []).every(value.containsKey)) return false;
   for(final entry in value.entries) {
    final p=properties[entry.key];
    if(p!=null) {if(!_matches(entry.value,p)) return false;}
    else if(schema['additionalProperties']==false) {return false;}
    else if(schema['additionalProperties'] is Map && !_matches(entry.value,schema['additionalProperties'])) {return false;}
   }
   return true;
 }
 return true;
}
const Map<String,Map<String,dynamic>> _schemas = '''+literal(schemas)+';\n'
(out/'wire_validation.dart').write_text(validation)
client=["// GENERATED by scripts/generate-dart-client.py. Do not edit.","import 'package:dio/dio.dart';","import '../session_transport.dart';","import 'models.dart';",'class ApiClient extends SessionTransport {',' ApiClient({required super.baseUrl,super.dio});']
# Raw envelopes must retain their original field presence and values after uncertain v1 submissions.
client += [" Future<StatusResponseDto> statusRaw(List<Map<String,dynamic>> operations) async => StatusResponseDto.fromJson(Map<String,dynamic>.from(await request('POST','/v1/sync/status',body:{'operations':operations})));",
" Future<SyncResponseDto> pushRaw(List<Map<String,dynamic>> operations) async => SyncResponseDto.fromJson(Map<String,dynamic>.from(await request('POST','/v1/sync/push',body:{'operations':operations})));",
" Future<Map<String,dynamic>> push(List<Map<String,dynamic>> operations) async => (await pushRaw(operations)).toJson();"]
for path,item in spec['paths'].items():
 for method,route in item.items():
  if method not in ['get','post','patch','put','delete']:continue
  name=route['operationId'][0].lower()+route['operationId'][1:];args=[];query=[];headers=[]
  for p in route.get('parameters',[]):
   n=p['name'];arg=n if re.match('^[a-zA-Z][a-zA-Z0-9]*$',n) else pascal(n);arg=arg[0].lower()+arg[1:]
   required=p.get('required',False);args.append(('required ' if required else '')+dtype(p['schema'])+('' if required else '?')+' '+arg)
   if p['in'] in ['query','header']:(query if p['in']=='query' else headers).append(('' if required else 'if('+arg+' != null) ')+literal(n)+': '+arg)
  body=route.get('requestBody',{}).get('content',{});binaryBody='application/octet-stream' in body
  if body:args.append('required '+('Stream<List<int>>' if binaryBody else dtype(body['application/json']['schema']))+' body')
  success=route['responses'].get('200',route['responses'].get('201'));media=next(iter(success['content']));resp=success['content'][media]['schema'];binary=media=='application/octet-stream';csv=media=='text/csv'
  if binary or binaryBody:args+=['CancelToken? cancelToken']
  endpoint=re.sub(r'\{(\w+)\}',lambda m:'${Uri.encodeComponent('+m[1]+')}',path)
  ret='ResponseBody' if binary else ('String' if csv else dtype(resp))
  client+=[f' Future<{ret}> {name}('+('{'+', '.join(args)+'}' if args else '')+') async {']
  if binary or binaryBody:
   if binaryBody:headers.append("'Content-Type':'application/octet-stream'")
   client+=[f"  final response=await transfer<{'ResponseBody' if binary else 'dynamic'}>('{method.upper()}','{endpoint}',"+('body:body,' if binaryBody else '')+('responseType:ResponseType.stream,' if binary else '')+'headers:{'+','.join(headers)+'},cancelToken:cancelToken);']
   client+=['  return '+('response.data!' if binary else decode(resp,'response.data'))+';']
  else:
   client+=[f"  final value=await request('{method.upper()}','{endpoint}',"+('body:body.toJson(),' if body else '')+'query:{'+','.join(query)+'});']
   client+=['  return '+('value as String' if csv else decode(resp,'value'))+';']
  client+=[' }']
client+=['}'];(out/'api_client.dart').write_text('\n'.join(client)+'\n')
examples=["// GENERATED transport contract decoder for real server fixtures.","import 'package:biobalance/data/services/api/generated/models.dart';",'Object? decodeResponse(String operationId,Object? value)=>switch(operationId){']
for path,item in spec['paths'].items():
 for method,route in item.items():
  if method not in ['get','post','patch','put','delete']:continue
  success=route['responses'].get('200',route['responses'].get('201'))
  schema=success.get('content',{}).get('application/json',{}).get('schema')
  if not schema:continue
  # Verify a complete decode/encode round-trip, including arrays and aliases.
  expression=encode(schema,'decoded')
  examples += [literal(route['operationId'])+' => (() {final decoded='+decode(schema,'value')+'; return '+expression+';})(),']
examples += ["_=>throw FormatException('Unknown operation $operationId'),",'};']
test_out=root/'apps/mobile/test/generated';test_out.mkdir(exist_ok=True)
(test_out/'contract_examples.dart').write_text('\n'.join(examples)+'\n')
# Formatting is part of generation, so CI compares byte-identical output.
dart=os.environ.get('DART_BIN','dart')
subprocess.run([dart,'format',str(out),str(test_out)],check=True)
subprocess.run([dart,'fix','--apply','--code=curly_braces_in_flow_control_structures,prefer_null_aware_operators,use_null_aware_elements,annotate_overrides',str(out)],check=True)
subprocess.run([dart,'format',str(out),str(test_out)],check=True)
print(f'Generated {len(schemas)} typed schemas and {sum(1 for p in spec["paths"].values() for m in p if m in ["get","post","patch","put","delete"])} endpoints.')
