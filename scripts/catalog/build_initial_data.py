#!/usr/bin/env python3
"""Build BioBalance's initial product data from the official list.

Sources, in order of trust:
  1. the workbook the business keeps (EAN + designation) — the list of record;
  2. biobalance.tn (name, French description, price, photo), already crawled in
     catalog.json by the earlier import;
  3. Barcode Lookup, for the products the site does not carry (relevé fait dans
     un navigateur : le site bloque les requêtes automatiques).
Nothing is invented: a price that no source gives stays empty and the product is
flagged. Output: produits.xlsx / .csv / .json, images/<EAN>.jpg, RAPPORT.md.
"""
import argparse, csv, json, pathlib, re, shutil, time
import openpyxl
import requests

CATEGORIES = {
    'maquillage': 'Maquillage', 'nettoyants-visage': 'Nettoyants visage', 'serum': 'Sérums',
    'soins-capillaires': 'Soins capillaires', 'soins-personnels': 'Soins personnels',
    'super-lift': 'Crèmes visage', 'supercreams-': 'Crèmes visage',
}
RANGES = ['Hello Clean', 'Acnevit', 'Dermasoothe', 'Dermasebum', 'Super Serum', 'LipojeN',
          'Dry & White', 'Dry & Sport', 'Super Cream', 'Super Toner']

# Products the website does not carry. Facts only (name, volume, actives, use), in
# French, taken from the Barcode Lookup sheet of each EAN. The price is left empty.
CURATED = {
    '8697711722011': dict(name='Eye Lash — sérum cils et sourcils 6 ml', range='', category='Soins du regard', size='6 ml',
        description='Sérum pour cils et sourcils aux peptides (Biotinoyl Tripeptide-1), à la biotine et à l’acide hyaluronique. Appliquer une fine ligne à la base des cils ou sur les sourcils, de préférence le soir, pendant au moins 30 jours.'),
    '8697711601514': dict(name='Hello Clean — baume nettoyant 3 en 1 Vitamine C pure 100 ml', range='Hello Clean', category='Nettoyants visage', size='100 ml',
        description='Baume nettoyant visage 3 en 1 à la vitamine C pure, pour peau terne. Sa texture sorbet se transforme en huile soyeuse au contact de la peau : il démaquille, nettoie et illumine. Spatule fournie.'),
    '8697711601538': dict(name='Hello Clean — baume nettoyant 3 en 1 Acide hyaluronique 100 ml', range='Hello Clean', category='Nettoyants visage', size='100 ml',
        description='Baume nettoyant visage 3 en 1 à l’acide hyaluronique, pour peau normale à sèche. Sa texture sorbet se transforme en huile soyeuse au contact de la peau : il démaquille, nettoie et hydrate. Spatule fournie.'),
    '8697711601521': dict(name='Hello Clean — baume nettoyant 3 en 1 Squalane 100 ml', range='Hello Clean', category='Nettoyants visage', size='100 ml',
        description='Baume nettoyant visage 3 en 1 au squalane et au bisabolol, pour peau sensible ou à rougeurs. Sa texture sorbet se transforme en huile soyeuse au contact de la peau : il démaquille, nettoie et apaise. Spatule fournie.'),
    '8697711601545': dict(name='Hello Clean — baume nettoyant 3 en 1 Acide oléanolique 100 ml', range='Hello Clean', category='Nettoyants visage', size='100 ml',
        description='Baume nettoyant visage 3 en 1 à l’acide oléanolique, pour peau grasse ou mixte : il contrôle l’excès de sébum et minimise les pores. Sa texture sorbet se transforme en huile soyeuse au contact de la peau. Spatule fournie.'),
    '8697711602139': dict(name='Super Serum — contour des yeux nuit 20 ml', range='Super Serum', category='Sérums', size='20 ml',
        description='Super sérum contour des yeux au phyto-rétinol (bakuchiol), aux céramides et à l’acide hyaluronique, anti-rides et réparateur intense. Appliquer une petite quantité sur peau propre et sèche, autour des yeux, par mouvements circulaires.'),
}
# Same product as another row of the list under an older code: reuse its price and photo.
SAME_AS = {'8697711622410': '8697711740411'}


def clean(text):
    return re.sub(r'\s+', ' ', (text or '').replace('\xa0', ' ')).strip()


def live_price(url):
    """The public price shown on a biobalance.tn product page, or None."""
    page = requests.get(url, headers={'User-Agent': 'BioBalance-catalog/1.0', 'Accept-Language': 'fr'}, timeout=30).text
    match = (re.search(r'property="product:price:amount" content="([\d.,]+)"', page)
             or re.search(r'itemprop="price" content="([\d.,]+)"', page))
    return float(match[1].replace(',', '.')) if match else None


def refresh_prices(rows):
    seen = {}
    for row in rows:
        url = row['source_url']
        if row['price_tnd'] is None or 'biobalance.tn' not in url:
            continue
        if url not in seen:
            seen[url] = live_price(url)
            time.sleep(0.8)
        price = seen[url]
        if price is not None and abs(price - row['price_tnd']) > 0.001:
            row['notes'] = (row['notes'] + ' · ' if row['notes'] else '') + f"Prix mis à jour depuis le site ({row['price_tnd']:g} → {price:g} TND)"
            row['price_tnd'] = price


def run(args):
    ws = openpyxl.load_workbook(args.workbook)['Feuil1']
    listed = [(str(r[0]), clean(r[1])) for r in ws.iter_rows(min_row=6, values_only=True) if r[0]]
    site = json.loads(args.catalog.read_text())['products']
    by_ean = {p['barcode']: p for p in site if p.get('barcode')}
    capture = json.loads(args.capture.read_text())['products']
    out = args.out
    (out / 'images').mkdir(parents=True, exist_ok=True)
    rows = []
    for ean, designation in listed:
        p = by_ean.get(ean)
        origin = p
        if not (p and p.get('priceMillimes')) and ean in SAME_AS:
            origin = by_ean.get(SAME_AS[ean])
        extra = CURATED.get(ean)
        row = dict(ean=ean, designation=designation, reference=(p or {}).get('reference') or f'BB-EAN-{ean}', notes=[])
        if origin and origin.get('priceMillimes'):
            url = origin.get('sourceUrl', '')
            seg = next((v for k, v in CATEGORIES.items() if f'/{k}/' in url), '')
            name = clean(origin['name'])
            row.update(name=name, category=seg, description=clean(origin['description']),
                       price_tnd=int(origin['priceMillimes']) / 1000, price_source=origin.get('priceSource', 'biobalance.tn'),
                       source_url=url)
            if origin is not p:
                row['notes'].append(f'Prix, photo et description repris du code {SAME_AS[ean]} (même produit, ancien code probable)')
        elif extra:
            row.update(name=extra['name'], category=extra['category'], description=extra['description'],
                       price_tnd=None, price_source='', source_url=f'https://www.barcodelookup.com/{ean}')
            row['notes'].append('Prix à fixer par BioBalance : absent du site et de la liste')
        else:
            row.update(name=clean(designation), category='', description='', price_tnd=None, price_source='', source_url='')
        full = f"{row['name']} {row['description']} {designation}"
        row['range'] = extra['range'] if extra else next((r for r in RANGES if r.lower() in full.lower()), '')
        size = re.search(r'\b(\d+(?:[.,]\d+)?)\s*(ml|g)\b', f"{row['name']} {designation}", re.I)
        row['size'] = extra['size'] if extra else (f'{size[1]} {size[2].lower()}' if size else '')
        # Photo: the website's own, else Barcode Lookup's, else the sibling code's.
        image, image_source = None, ''
        for key in (ean, SAME_AS.get(ean)):
            if not key:
                continue
            site_row = by_ean.get(key)
            candidate = site_row and site_row.get('imageFile') and args.site_images / pathlib.Path(site_row['imageFile']).name
            if candidate and candidate.exists():
                image, image_source = candidate, site_row.get('sourceUrl', 'biobalance.tn')
                break
            candidate = args.sources / f'bl-{key}.jpg'
            if candidate.exists():
                image, image_source = candidate, f'https://www.barcodelookup.com/{key}'
                break
        if image:
            shutil.copyfile(image, out / 'images' / f'{ean}.jpg')
        row['image'] = f'images/{ean}.jpg' if image else ''
        row['image_source'] = image_source
        missing = [label for label, ok in (('prix', row['price_tnd'] is not None), ('photo', bool(image))) if not ok]
        row['status'] = 'complet' if not missing else 'à compléter : ' + ' + '.join(missing)
        row['notes'] = ' · '.join(row['notes'])
        rows.append(row)
    if args.refresh_prices:
        refresh_prices(rows)
    off_list = [p for p in site if not p.get('barcode')]
    write(out, rows, off_list, capture)


COLUMNS = [('ean', 'EAN'), ('reference', 'Référence interne'), ('designation', 'Désignation (liste BioBalance)'),
           ('name', 'Nom affiché'), ('range', 'Gamme'), ('category', 'Catégorie'), ('size', 'Contenance'),
           ('description', 'Description'), ('price_tnd', 'Prix de vente conseillé (TND)'),
           ('price_source', 'Source du prix'), ('image', 'Image'), ('image_source', 'Source de l’image'),
           ('status', 'Statut'), ('notes', 'Remarques')]


def write(out, rows, off_list, capture):
    (out / 'produits.json').write_text(json.dumps(rows, ensure_ascii=False, indent=1))
    with (out / 'produits.csv').open('w', newline='', encoding='utf-8-sig') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow([label for _, label in COLUMNS])
        for r in rows:
            w.writerow([r[k] if r[k] is not None else '' for k, _ in COLUMNS])
    wb = openpyxl.Workbook()
    sheet = wb.active
    sheet.title = 'Produits'
    sheet.append([label for _, label in COLUMNS])
    for r in rows:
        sheet.append([r[k] if r[k] is not None else '' for k, _ in COLUMNS])
    for col, width in zip('ABCDEFGHIJKLMN', (16, 22, 44, 48, 14, 18, 11, 70, 14, 14, 26, 36, 26, 50)):
        sheet.column_dimensions[col].width = width
    sheet.freeze_panes = 'D2'
    extra = wb.create_sheet('Hors liste (site seulement)')
    extra.append(['Référence', 'Nom', 'Prix (TND)', 'Page', 'Remarque'])
    for p in off_list:
        extra.append([p['reference'], clean(p['name']), int(p['priceMillimes']) / 1000 if p.get('priceMillimes') else '',
                      p.get('sourceUrl', ''), 'Sur le site, pas dans votre liste, sans code-barres'])
    wb.save(out / 'produits.xlsx')
    done = sum(r['status'] == 'complet' for r in rows)
    lines = [f'# Données initiales — {len(rows)} produits de votre liste', '',
             f'- **Complets (nom, description, prix, photo) : {done}**',
             f'- À compléter : {len(rows) - done}', '']
    for r in rows:
        if r['status'] != 'complet':
            lines.append(f"- `{r['ean']}` {r['name']} — {r['status']}" + (f" ({r['notes']})" if r['notes'] else ''))
    lines += ['', f'Produits du site hors de votre liste (sans code-barres) : {len(off_list)} (feuille « Hors liste »).', '',
              'Les prix viennent de biobalance.tn (prix de vente public). Aucun prix n’a été inventé.',
              'Les photos de Barcode Lookup viennent de revendeurs : à remplacer par vos visuels officiels si vous en avez.']
    (out / 'RAPPORT.md').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    root = pathlib.Path(__file__).resolve().parents[2]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--workbook', type=pathlib.Path, required=True)
    ap.add_argument('--catalog', type=pathlib.Path, default=root / '.artifacts/catalog-operations-2026-09-22/catalog.json')
    ap.add_argument('--site-images', type=pathlib.Path, default=root / '.artifacts/catalog-operations-2026-09-22/images')
    ap.add_argument('--sources', type=pathlib.Path, default=root / 'data/initial-catalog/sources')
    ap.add_argument('--capture', type=pathlib.Path, default=root / 'data/initial-catalog/sources/barcodelookup-capture.json')
    ap.add_argument('--refresh-prices', action='store_true', help='re-read each price on biobalance.tn')
    ap.add_argument('--out', type=pathlib.Path, default=root / 'data/initial-catalog')
    run(ap.parse_args())
