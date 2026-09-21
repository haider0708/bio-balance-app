#!/usr/bin/env python3
"""Generate the project's JSON/Dio transport from the checked-in OpenAPI contract.
Object and union payloads remain transport maps; domain validation is separate.
"""
import json,re,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
spec=json.loads((root/'contracts/openapi/biobalance.json').read_text())
out=root/'apps/mobile/lib/data/services/api/generated'
out.mkdir(parents=True,exist_ok=True)
def dtype(p):
 if '$ref' in p:return p['$ref'].split('/')[-1]+'Dto'
 return {'string':'String','integer':'int','number':'double','boolean':'bool','array':'List<dynamic>','object':'Map<String, dynamic>'}.get(p.get('type'),'dynamic')
lines=['// GENERATED from contracts/openapi/biobalance.json. Do not edit.','']
for name,schema in spec['components']['schemas'].items():
 if schema.get('type')!='object':continue
 props=schema.get('properties',{});required=schema.get('required',[]);classname=name+'Dto'
 lines += ['class '+classname+' {']
 for field,p in props.items():
  kind=dtype(p);nullable='' if field in required or kind=='dynamic' else '?';lines+=['  final '+kind+nullable+' '+field+';']
 lines+=['  const '+classname+'({'+', '.join(('required ' if f in required else '')+'this.'+f for f in props)+'});']
 lines+=['  factory '+classname+'.fromJson(Map<String, dynamic> json) => '+classname+'(']
 for field,p in props.items():
  kind=dtype(p);access="json['"+field+"']";expr=access
  if kind.endswith('Dto'):expr=kind+'.fromJson(Map<String, dynamic>.from('+access+'))'
  elif kind=='Map<String, dynamic>':expr='Map<String, dynamic>.from('+access+')'
  elif kind=='List<dynamic>':expr='List<dynamic>.from('+access+')'
  elif kind=='int':expr='('+access+' as num).toInt()'
  elif kind=='double':expr='('+access+' as num).toDouble()'
  elif kind!='dynamic':expr=access+' as '+kind
  if field not in required and kind!='dynamic':expr=access+' == null ? null : '+expr
  lines+=['    '+field+': '+expr+',']
 lines+=['  );','  Map<String, dynamic> toJson() => {']
 for field,p in props.items():
  val=field+('?.toJson()' if field not in required else '.toJson()') if dtype(p).endswith('Dto') else field
  lines+=['    '+('if ('+field+' != null) ' if field not in required else '')+"'"+field+"': "+val+',']
 lines+=['  };','}','']
(out/'models.dart').write_text('\n'.join(lines))
client='''// GENERATED from contracts/openapi/biobalance.json. Do not edit.
import 'package:dio/dio.dart';
class ApiClient {
 final Dio http;
 String? accountId;
 ApiClient({required String baseUrl,Dio? dio}):http=dio??Dio(BaseOptions(baseUrl:baseUrl,connectTimeout:const Duration(seconds:8),receiveTimeout:const Duration(seconds:20)));
 void authenticate(String? token,{String? accountId}) { this.accountId=accountId; if(token==null){http.options.headers.remove('Authorization');}else{http.options.headers['Authorization']='Bearer $token';} }
 Future<dynamic> request(String method,String path,{dynamic body,Map<String,dynamic>? query}) async => (await http.request<dynamic>(path,data:body,queryParameters:query,options:Options(method:method))).data;
 Future<Map<String,dynamic>> push(List<Map<String,dynamic>> operations) async => Map<String,dynamic>.from(await request('POST','/v1/sync/push',body:{'operations':operations}));
 Future<Map<String,dynamic>> snapshot(String storeId,String organizationId) async => Map<String,dynamic>.from(await request('GET','/v1/stores/$storeId/snapshot',query:{'organizationId':organizationId}));
'''
for path,item in spec['paths'].items():
 for method,route in item.items():
  if method not in ['get','post','patch','put','delete']:continue
  name=route.get('operationId',method+path);name=re.sub('[^A-Za-z0-9_]','',name);name=name[0].lower()+re.sub(r'_([a-zA-Z])',lambda m:m[1].upper(),name[1:])
  pathparams=re.findall(r'\{(\w+)\}',path)
  args=['required String '+v for v in pathparams]+['Map<String,dynamic>? query','dynamic body']
  interpolated=re.sub(r'\{(\w+)\}',lambda m:'${Uri.encodeComponent('+m[1]+')}',path)
  client+=' Future<dynamic> '+name+'({'+','.join(args)+'}) => request(\''+method.upper()+"','"+interpolated+"',query:query,body:body);\n"
client+='}\n';(out/'api_client.dart').write_text(client)
print('Generated transport models and',sum(len(p) for p in spec['paths'].values()),'route methods.')
