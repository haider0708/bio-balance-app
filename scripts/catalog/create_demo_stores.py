#!/usr/bin/env python3
import argparse,json,pathlib
from operator_client import Client,save_json
p=argparse.ArgumentParser();p.add_argument('--directory',type=pathlib.Path,required=True);p.add_argument('--sources',type=pathlib.Path,required=True);p.add_argument('--admin-file',type=pathlib.Path,required=True);p.add_argument('--base-url',required=True);a=p.parse_args()
manifest=json.loads((a.directory/'demo-private.json').read_text());sources=json.loads(a.sources.read_text())
if manifest['dataset']!='biobalance-demo-2026-09' or len(sources)>10:raise ValueError('Demo dataset required')
c=Client(a.base_url,json.loads(a.admin_file.read_text()),a.directory)
try:
    stores=c.call('GET','/v1/stores');result=[]
    for s in sources:
        if not s['name'].startswith('DÉMO — '):raise ValueError('Demo prefix required')
        org=manifest['organizations'][s['organizationIndex']]['id']
        candidates=[x for x in stores if x['organizationId']==org and x['name']==s['name']]
        if len(candidates)>1:raise ValueError('Ambiguous existing store')
        fields={k:s[k] for k in ('name','address','city')};fields['organizationId']=org
        store=candidates[0] if candidates else c.call('POST','/v1/stores',fields,expected=201)
        if any(store[k]!=v for k,v in fields.items()):raise ValueError('Existing store differs')
        result.append({**s,**store})
        save_json(a.directory/'stores-created.json',result)
    members=[]
    for store in result:
        user=next(u for u in manifest['users'] if u['email']==store['slug']+'@demo.biobalance.invalid')
        members.append({'userId':user['id'],'storeId':store['id'],'organizationId':store['organizationId'],'permissions':['sell','receive']})
    manifest['memberships']=members;save_json(a.directory/'demo-private.json',manifest)
    print(json.dumps({'stores':len(result),'membershipsPrepared':len(members)}))
finally:c.close()
