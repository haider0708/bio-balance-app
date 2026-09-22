#!/usr/bin/env python3
"""Create a small explicit demonstration through normal store/ledger APIs."""
import argparse,datetime,hashlib,html,json,pathlib,time,uuid
from operator_client import Client,ApiError,save_json

def main(a):
 root=a.directory; manifest=json.loads((root/'demo-private.json').read_text());stores=json.loads((root/'stores-created.json').read_text());catalog=json.loads(a.catalog.read_text());imported=json.loads((root/'import-state.json').read_text())['products']
 if manifest['dataset']!='biobalance-demo-2026-09' or any(not s['name'].startswith('DÉMO — ') for s in stores):raise ValueError('Explicit demo dataset required')
 state_file=root/'simulation-state.json';digest=hashlib.sha256(a.catalog.read_bytes()).hexdigest()
 state=json.loads(state_file.read_text()) if state_file.exists() else {'api':a.base_url,'manifestSha256':digest,'ids':{},'commands':{},'finished':[],'date':datetime.datetime.now(datetime.timezone.utc).date().isoformat()}
 if state['api']!=a.base_url or state['manifestSha256']!=digest:raise ValueError('Simulation state scope mismatch')
 def save():save_json(state_file,state)
 def ident(key):
  if key not in state['ids']:state['ids'][key]=str(uuid.uuid4());save()
  return state['ids'][key]
 def op(client,store,key,factory,version=None):
  key=store['slug']+'/'+key
  if key not in state['commands']:
   value={'operationId':str(uuid.uuid4()),'organizationId':store['organizationId'],'storeId':store['id'],'payloadVersion':2,'dependencies':[],'command':factory()}
   if version is not None:value['expectedVersion']=version
   state['commands'][key]={'actorId':client.actor_id,'envelope':value};save()
  entry=state['commands'][key]
  if entry['actorId']!=client.actor_id:raise ValueError('Command account mismatch')
  # Replay exact persisted operation even after a lost response; no new operation ID.
  result=client.call('POST','/v1/sync/push',{'operations':[entry['envelope']]},expected=201)['results'][0]
  if result['status']!='accepted':raise ValueError(key+': '+result.get('code','not accepted'))
  if entry.get('result') and entry['result']!=result:raise ValueError('Idempotency result changed')
  entry['result']=result;save();return result['data']
 clients=[]
 def connect(credentials):
  c=Client(a.base_url,credentials,root);c.actor_id=c.call('GET','/v1/identity/me')['id'];clients.append(c);return c
 def route(s,path):return '/v1/stores/'+s['id']+path+'?organizationId='+s['organizationId']
 admin=connect(json.loads(a.admin_file.read_text()))
 products=[dict(p,id=imported[p['reference']]['id']) for p in catalog['products'] if p['active']]
 day=datetime.date.fromisoformat(state['date']);valid=(day+datetime.timedelta(days=540)).isoformat()
 owners={}
 try:
  for store_index,s in enumerate(stores):
   org=s['organizationId']
   if org not in owners:owners[org]=connect(next(u for u in manifest['users'] if u['organizationId']==org and u['owner']))
   manager=owners[org];seller=connect(next(u for u in manifest['users'] if u['email']==s['slug']+'@demo.biobalance.invalid'))
   configs=manager.call('GET',route(s,'/collections/config'));existing={x['productId']:x for x in configs}
   for i,p in enumerate(products):
    wanted={'priceMillimes':p['priceMillimes'],'threshold':5,'pointsPerUnit':10 if 'serum' in p['name'].lower() else 5}
    old=existing.get(p['id'])
    if old:
     if any(str(old[k])!=str(v) for k,v in wanted.items()):raise ValueError('Existing demo configuration modified')
    else:
     manager.call('PATCH',route(s,'/products/'+p['id']),wanted);time.sleep(.12)
   lines=[{'productId':p['id'],'batch':'DEMO-'+s['slug'].upper()+'-202609-'+str(i+1).zfill(2),'expiry':valid,'quantity':50 if i==0 else 4 if i==1 else 2 if i==2 else 18+(i+store_index)%15} for i,p in enumerate(products)]
   lines += [{'productId':products[4]['id'],'batch':'DEMO-EXPIRY-SOON','expiry':(day+datetime.timedelta(days=20)).isoformat(),'quantity':3},{'productId':products[5]['id'],'batch':'DEMO-EXPIRED','expiry':(day-datetime.timedelta(days=7)).isoformat(),'quantity':2}]
   op(manager,s,'opening',lambda:{'type':'stock.receive','reason':'opening','lines':lines})
   lots=manager.call('GET',route(s,'/collections/lots'));by_product={x['productId']:x for x in lots if x['batch'].startswith('DEMO-'+s['slug'].upper()+'-')}
   for i,p in enumerate(products[:20]):
    saleid=ident(s['slug']+'/sale/'+str(i));lineid=ident(s['slug']+'/line/'+str(i));lot=by_product[p['id']]
    def sale(p=p,i=i,saleid=saleid,lineid=lineid,lot=lot):
     date=datetime.datetime.combine(day-datetime.timedelta(days=i%7),datetime.time(10,15),datetime.timezone.utc).isoformat()
     return {'type':'sale.create','saleId':saleid,'occurredAt':date,'lines':[{'id':lineid,'productId':p['id'],'quantity':7 if i==2 else 2,'unitPriceMillimes':p['priceMillimes'],'allocations':[{'lotId':lot['id'],'quantity':7 if i==2 else 2}]}]}
    op(seller,s,'sale/'+str(i),sale)
   original=state['commands'][s['slug']+'/sale/0']['envelope']['command'];corrected=json.loads(json.dumps(original));corrected.update(type='sale.correct',reason='DÉMO : correction de quantité');corrected['lines'][0]['quantity']=3;corrected['lines'][0]['allocations'][0]['quantity']=3
   op(seller,s,'correct',lambda:corrected,1)
   op(seller,s,'return',lambda:{'type':'sale.return','saleId':original['saleId'],'reason':'DÉMO : retour client revendable','lines':[{'lineId':original['lines'][0]['id'],'lotId':original['lines'][0]['allocations'][0]['lotId'],'quantity':1,'sellable':True}]},2)
   lots=manager.call('GET',route(s,'/collections/lots'));lot=next(x for x in lots if x['id']==by_product[products[0]['id']]['id'])
   op(manager,s,'damage',lambda:{'type':'stock.damage','lotId':lot['id'],'quantity':1,'reason':'DÉMO : emballage abîmé'},lot['version'])
   snapshot=manager.call('GET',route(s,'/snapshot')+'&protocol=3');rewards=snapshot['rewards']
   for index,p in enumerate(products[:2]):
    title='DÉMO — '+('Produit offert' if index==0 else 'Bon cadeau')
    wanted={'title':title,'description':'Récompense de simulation, sans valeur réelle.','cost':20 if index==0 else 10,'quantity':1,'active':True}
    if index==0:wanted['productId']=p['id']
    matching=[r for r in rewards if r['title']==title]
    if len(matching)>1:raise ValueError('Ambiguous reward')
    reward=matching[0] if matching else manager.call('POST',route(s,'/rewards'),wanted,expected=201)
    claim=ident(s['slug']+'/claim/'+str(index))
    op(seller,s,'claim/'+str(index),lambda:{'type':'reward.request','claimId':claim,'rewardId':reward['id']})
    if index==0:op(manager,s,'fulfill',lambda:{'type':'reward.resolve','claimId':claim,'decision':'fulfilled'},1)
   order=ident(s['slug']+'/order');product=products[1]['id']
   op(manager,s,'order',lambda:{'type':'order.create','orderId':order,'lines':[{'productId':product,'quantity':12}]})
   if store_index<4:op(admin,s,'prepare',lambda:{'type':'order.prepare','orderId':order},1)
   if store_index<3:
    delivery=ident(s['slug']+'/delivery')
    op(admin,s,'dispatch',lambda:{'type':'delivery.dispatch','orderId':order,'deliveryId':delivery,'lines':[{'productId':product,'quantity':12}]},2)
    received=12 if store_index==0 else 8 if store_index==1 else 0
    op(seller,s,'receive',lambda:{'type':'delivery.receive','deliveryId':delivery,'lines':[{'productId':product,'batch':'DEMO-DELIVERY-202609','expiry':valid,'quantity':received}] if received else [],'note':'DÉMO : livraison complète' if received==12 else 'DÉMO : colis incomplet' if received else 'DÉMO : colis non reçu'},1)
    fulfillment=manager.call('GET',route(s,'/orders/'+order+'/fulfillment'))
    if store_index==1:
     remaining=fulfillment['lines'][0]['remainingToDispatch']
     op(admin,s,'follow-up',lambda:{'type':'delivery.dispatch','orderId':order,'deliveryId':ident(s['slug']+'/follow-up-delivery'),'lines':[{'productId':product,'quantity':remaining}]},fulfillment['version'])
   announcement={'id':ident(s['slug']+'/announcement'),'title':'Bienvenue dans le magasin de démonstration','body':'Les stocks, lots, ventes et récompenses de ce magasin sont fictifs. Utilisez-les pour découvrir le parcours avant de saisir les données réelles.','audience':'salespeople'}
   manager.call('POST',route(s,'/announcements'),announcement,expected=201)
   manager.call('PATCH',route(s,'/onboarding'),{'step':5})
   state['finished']=list(set(state['finished']+[s['slug']]));save()
   print('Demo workflow verified:',s['slug'],flush=True)
  # A published application guide contains no invented product/medical assertions.
  admin.call('POST','/v1/training',{'submissionId':ident('training/guide'),'title':'Premiers pas — environnement de démonstration','type':'article','status':'published','productIds':[],'body':'<p>Les magasins dont le nom commence par DÉMO contiennent des données fictives.</p><h2>Vendre</h2><p>Choisissez le magasin, scannez ou cherchez un produit, vérifiez le lot, la quantité et le prix puis enregistrez. Les opérations hors connexion restent en attente de synchronisation.</p><h2>Corriger et retourner</h2><p>Ouvrez la vente d’origine et indiquez un motif. Les mouvements de stock et les points sont ajustés avec un historique.</p><h2>Récompenses</h2><p>La demande réserve des points. Le responsable confirme la remise pour les déduire.</p>'},expected=201)
  for p in products[:5]:
   admin.call('POST','/v1/training',{'submissionId':ident('training/'+p['reference']),'title':p['name'][:170]+' — fiche à relire','type':'article','status':'draft','productIds':[p['id']],'body':'<p>'+html.escape(p['description'])+'</p><p>Source : '+html.escape(p['sourceUrl'])+'</p><p>Fiche importée à relire par BioBalance avant publication.</p>'},expected=201)
  print(json.dumps({'stores':len(state['finished']),'acceptedCommands':len(state['commands']),'training':'one published guide and five product drafts'}))
 finally:
  for c in reversed(clients):
   try:c.close()
   except Exception:pass
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--directory',type=pathlib.Path,required=True);p.add_argument('--catalog',type=pathlib.Path,required=True);p.add_argument('--admin-file',type=pathlib.Path,required=True);p.add_argument('--base-url',required=True);main(p.parse_args())
