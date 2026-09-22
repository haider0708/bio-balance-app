#!/usr/bin/env python3
"""Resume a reviewed catalog import through the authenticated production API.

No overwrites of foreign products, no zero-price fallback, no direct ledger writes.
The state directory must be private and dedicated to one API/account/manifest.
"""
import argparse, hashlib, json, pathlib, time
from operator_client import Client, save_json


def validate(document):
    products=document['products']
    if document['schemaVersion']!=1 or not 1<=len(products)<=200:raise ValueError('Unsupported manifest')
    refs=set(); codes=set()
    for p in products:
        if p['reference'] in refs or not p['reference'].startswith(('BB-WEB-','BB-EAN-')):raise ValueError('Duplicate/invalid reference')
        refs.add(p['reference'])
        code=p.get('barcode')
        if code:
            if len(code)!=13 or not code.isascii() or not code.isdigit() or code in codes:raise ValueError('Invalid/duplicate barcode')
            if sum(int(c)*(1 if i%2==0 else 3) for i,c in enumerate(code))%10:raise ValueError('Invalid EAN checksum')
            codes.add(code)
        price=p.get('priceMillimes')
        if price is not None and (not isinstance(price,str) or not price.isascii() or not price.isdigit() or int(price)<=0):raise ValueError('Invalid sourced price')
        if p['active'] and (price is None or not p.get('imageFile')):raise ValueError('Active product needs sourced price and image')
    return products


def run(args):
    root=args.manifest.parent.resolve(); document=json.loads(args.manifest.read_text()); products=validate(document)
    digest=hashlib.sha256(args.manifest.read_bytes()).hexdigest()
    args.state_dir.mkdir(mode=0o700,parents=True,exist_ok=True)
    state_file=args.state_dir/'import-state.json'
    state=json.loads(state_file.read_text()) if state_file.exists() else {'manifestSha256':digest,'api':args.base_url,'products':{}}
    if state['manifestSha256']!=digest or state['api']!=args.base_url:raise ValueError('State belongs to another manifest/API')
    for p in products:
        if p.get('imageFile'):
            image=(root/p['imageFile']).resolve()
            if not image.is_relative_to(root) or image.is_symlink() or image.stat().st_size>10*1024*1024:raise ValueError('Invalid media file')
            if hashlib.sha256(image.read_bytes()).hexdigest()!=p['imageSha256']:raise ValueError('Source image changed')
    if not args.apply:
        print(json.dumps({'validatedProducts':len(products),'active':sum(p['active'] for p in products),'apply':False}));return
    client=Client(args.base_url,json.loads(args.admin_file.read_text()),args.state_dir)
    try:
        me=client.call('GET','/v1/identity/me')
        if not me['platformAdmin']:raise ValueError('Administrator required')
        if state.get('actorId',me['id'])!=me['id']:raise ValueError('State belongs to another account')
        state['actorId']=me['id'];save_json(state_file,state)
        query='?organizationId='+args.organization
        route='/v1/stores/'+args.store+'/collections/products'+query
        existing=[];after=None
        while True:
            page=client.call('GET',route+('&after='+after if after else ''))
            existing.extend(page)
            if len(page)<200:break
            after=page[-1]['id']
            if len(existing)>10000:raise ValueError('Catalog page bound')
        by_ref={p['reference']:p for p in existing}
        for p in products:
            fields={k:p[k] for k in ('reference','name','description','active')}
            if p.get('barcode'):fields['barcode']=p['barcode']
            item=state['products'].setdefault(p['reference'],{})
            current=by_ref.get(p['reference'])
            if current:
                # Lost POST responses recover only an exact import, never replace a business edit.
                if any(current.get(k)!=v for k,v in fields.items()):raise ValueError('Existing catalog differs: '+p['reference'])
                if item.get('id',current['id'])!=current['id']:raise ValueError('Catalog identity changed')
            else:
                item['creationAttempted']=True;save_json(state_file,state)
                current=client.call('POST','/v1/catalog/products',fields,expected=201)
            item.update({'id':current['id'],'version':current['version']});save_json(state_file,state)
            if p.get('imageFile'):
                content=(root/p['imageFile']).read_bytes()
                asset=client.call('POST','/v1/media/uploads',{'purpose':'catalog','fileName':p['reference']+'.jpg','mime':'image/jpeg' if content[:2]==b'\xff\xd8' else 'image/png','size':len(content),'sha256':p['imageSha256']},expected=201)
                item['mediaId']=asset['id'];save_json(state_file,state)
                upload='/v1/media/uploads/'+asset['id']
                status=client.call('GET',upload)
                while status['status']=='uploading' and int(status['received'])<len(content):
                    offset=int(status['received']); chunk=content[offset:offset+512*1024]
                    client.call('PUT',upload,chunk,headers={'Content-Type':'application/octet-stream','Upload-Offset':str(offset)})
                    status=client.call('GET',upload)
                deadline=time.monotonic()+180
                while status['status']!='ready' and time.monotonic()<deadline:
                    if status['status'] not in {'uploading','processing'}:raise ValueError('Media processing failed')
                    time.sleep(1);status=client.call('GET',upload)
                if status['status']!='ready':raise ValueError('Media processing timeout')
                meta=client.call('GET','/v1/media/'+asset['id']+'/metadata')
                image=client.call('GET','/v1/media/'+asset['id'],raw=True)
                if len(image)!=int(meta['size']) or hashlib.sha256(image).hexdigest()!=meta['sha256']:raise ValueError('Processed image mismatch')
                if current.get('imageId')!=asset['id']:
                    current=client.call('POST','/v1/catalog/products',{**fields,'id':current['id'],'expectedVersion':current['version'],'imageId':asset['id']},expected=201)
                item.update({'version':current['version'],'imageVerified':True,'processedSha256':meta['sha256'],'processedBytes':len(image)})
            item['complete']=True;save_json(state_file,state)
            print('Imported',p['reference'],flush=True)
        print(json.dumps({'products':len(products),'imagesVerified':sum(bool(p.get('imageVerified')) for p in state['products'].values())}))
    finally:client.close()

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--manifest',type=pathlib.Path,required=True);parser.add_argument('--state-dir',type=pathlib.Path,required=True);parser.add_argument('--admin-file',type=pathlib.Path,required=True);parser.add_argument('--base-url',required=True);parser.add_argument('--organization',required=True);parser.add_argument('--store',required=True);parser.add_argument('--apply',action='store_true');run(parser.parse_args())
