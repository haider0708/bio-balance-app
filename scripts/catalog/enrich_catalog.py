#!/usr/bin/env python3
"""Add reviewed product metadata without changing store prices or business IDs."""
import argparse, hashlib, json, pathlib, re, urllib.parse
from operator_client import Client, save_json


def prepare(catalog, samples):
    sample = {p['reference']: p for p in samples['products']}
    categories = {'maquillage':'Maquillage','nettoyants-visage':'Nettoyants visage','serum':'Sérums','soins-capillaires':'Soins capillaires','soins-personnels':'Soins personnels','super-lift':'Crèmes visage','supercreams-':'Crèmes visage'}
    output=[]
    for p in catalog['products']:
        extra=sample.get(p['reference'],{})
        description=p['description']
        source=extra.get('sourceUrl') or p.get('sourceUrl')
        match=re.search(r'(?:Conseils? d[’\']utilisation|Mode d[’\']emploi)\s*:\s*(.+)',description,re.I)
        instructions=match.group(1).strip() if match else ''
        package=re.search(r'\b(\d+(?:[.,]\d+)?)\s*(ml|g)\b',p['name']+' '+description,re.I)
        name=p['name']
        group=next((v for k,v in categories.items() if '/'+k+'/' in (source or '')), '')
        if not group and p['reference'] in sample:
            group='Nettoyants visage' if 'H.C ' in name else 'Soins personnels' if 'DEO ' in name else 'Soins du regard'
        ranges=['Hello Clean','Acnevit','Dermasoothe','Dermasebum','Super Serum','LipojeN','Dry & White','Dry & Sport','Super Cream']
        line=next((r for r in ranges if r.lower() in (name+' '+description).lower()),'')
        # Only copy explicitly sourced contents. A benefit mentioning one active
        # ingredient is not treated as a complete INCI list.
        fields={'category':group,'range':line,'packageSize':f'{package[1]} {package[2].lower()}' if package else '',
            'instructions':instructions,'referencePriceMillimes':extra.get('priceMillimes') or p.get('priceMillimes'),
            'priceStatus':'sample' if extra else 'verified' if p.get('priceMillimes') else 'missing',
            'sourceUrls':[source] if source else []}
        output.append({'reference':p['reference'],'barcode':p.get('barcode'),'sourceName':name,'fields':fields})
    if len(output)!=51 or len({p['reference'] for p in output})!=51:raise ValueError('Expected reviewed 51-product catalog')
    return output


def run(args):
    source=json.loads(args.catalog.read_text());samples=json.loads(args.samples.read_text())
    rows=prepare(source,samples)
    if args.workbook and hashlib.sha256(args.workbook.read_bytes()).hexdigest()!=source['sourceWorkbookSha256']:
        raise ValueError('Workbook changed; barcode reconciliation must be reviewed')
    args.state_dir.mkdir(parents=True,exist_ok=True,mode=0o700)
    save_json(args.state_dir/'reviewed-metadata.json',{'sourceRetrievedAt':source['retrievedAt'],'rows':rows})
    print(json.dumps({'products':len(rows),'barcodes':sum(bool(p['barcode']) for p in rows),'samplePrices':sum(p['fields']['priceStatus']=='sample' for p in rows),'instructions':sum(bool(p['fields']['instructions']) for p in rows),'packageSizes':sum(bool(p['fields']['packageSize']) for p in rows),'apply':args.apply}))
    if not args.apply:return
    client=Client(args.base_url,json.loads(args.admin_file.read_text()),args.state_dir)
    try:
        products=[];after=None
        while True:
            page=client.call('GET','/v1/catalog/products'+('?after='+after if after else ''))
            products+=page['items'];after=page['nextCursor']
            if after is None:break
        indexed={p['reference']:p for p in products}
        before=args.state_dir/'before.json'
        if not before.exists():save_json(before,products)
        changed=0
        for row in rows:
            current=indexed.get(row['reference'])
            if current is None or current.get('barcode')!=row['barcode'] or not current.get('imageId'):
                raise ValueError('Identity/image mismatch: '+row['reference'])
            fields=row['fields']
            for field,value in fields.items():
                if current.get(field) not in (None,'',[], 'missing',value):
                    raise ValueError('Existing business edit requires review: '+row['reference']+' '+field)
            name=current['name']
            if fields['priceStatus']=='sample':name=re.sub(r'\s*[—–-]?\s*[\[(]?prix démo[\])]?\s*$','',name,flags=re.I).strip()
            if name==current['name'] and all(current.get(k)==v for k,v in fields.items()):continue
            payload={k:current[k] for k in ['reference','description','active','imageId']}
            if current.get('barcode'):payload['barcode']=current['barcode']
            client.call('POST','/v1/catalog/products',{**payload,**fields,'name':name,'id':current['id'],'expectedVersion':current['version']},expected=201)
            changed+=1
        save_json(args.state_dir/'result.json',{'changed':changed,'reviewed':51,'storePricesChanged':False})
        print(json.dumps({'changed':changed,'storePricesChanged':False}))
    finally:client.close()

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--catalog',type=pathlib.Path,required=True);parser.add_argument('--samples',type=pathlib.Path,required=True);parser.add_argument('--workbook',type=pathlib.Path);parser.add_argument('--state-dir',type=pathlib.Path,required=True);parser.add_argument('--base-url');parser.add_argument('--admin-file',type=pathlib.Path);parser.add_argument('--apply',action='store_true');run(parser.parse_args())
