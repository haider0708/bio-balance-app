#!/usr/bin/env python3
"""Build BioBalance's initial product data from the official list.

Sources, in order of trust:
  1. the workbook the business keeps (EAN + designation) — the list of record;
  2. biobalance.tn (name, French description, price, photo), already crawled in
     catalog.json by the earlier import;
  3. Barcode Lookup, for the products the site does not carry (relevé fait dans
     un navigateur : le site bloque les requêtes automatiques).
Prices are deliberately left out: BioBalance sets them in the app. Nothing is
invented. Output: produits.xlsx / .csv / .json, images/<EAN>.jpg, RAPPORT.md.
"""
import argparse, csv, json, pathlib, re, shutil
import openpyxl

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


def run(args):
    ws = openpyxl.load_workbook(args.workbook)['Feuil1']
    listed = [(str(r[0]), clean(r[1])) for r in ws.iter_rows(min_row=6, values_only=True) if r[0]]
    site = json.loads(args.catalog.read_text())['products']
    by_ean = {p['barcode']: p for p in site if p.get('barcode')}
    out = args.out
    (out / 'images').mkdir(parents=True, exist_ok=True)
    rows = []
    for ean, designation in listed:
        own = by_ean.get(ean)
        # A code whose own page has no data reuses the sibling code's (same product, older code).
        origin = own if own and own.get('description') and own.get('imageFile') else by_ean.get(SAME_AS.get(ean, ''), own)
        curated = CURATED.get(ean)
        row = dict(ean=ean, reference=(own or {}).get('reference') or f'BB-EAN-{ean}', designation=designation, notes=[])
        if curated:
            row.update(name=curated['name'], category=curated['category'], description=curated['description'],
                       source_url=f'https://www.barcodelookup.com/{ean}')
        elif origin and origin.get('description'):
            url = origin.get('sourceUrl', '')
            row.update(name=clean(origin['name']), description=clean(origin['description']), source_url=url,
                       category=next((v for k, v in CATEGORIES.items() if f'/{k}/' in url), ''))
            if origin is not own:
                row['notes'].append(f'Données et photo reprises du code {SAME_AS[ean]} (même produit, ancien code probable)')
        else:
            row.update(name=clean(designation), category='', description='', source_url='')
        full = f"{row['name']} {row['description']} {designation}"
        row['range'] = curated['range'] if curated else next((r for r in RANGES if r.lower() in full.lower()), '')
        size = re.search(r'\b(\d+(?:[.,]\d+)?)\s*(ml|g)\b', f"{row['name']} {designation}", re.I)
        row['size'] = curated['size'] if curated else (f'{size[1]} {size[2].lower()}' if size else '')
        image, image_source = None, ''
        for key in (ean, SAME_AS.get(ean)):
            if not key or image:
                continue
            site_row = by_ean.get(key)
            file = site_row and site_row.get('imageFile') and args.site_images / pathlib.Path(site_row['imageFile']).name
            if file and file.exists():
                image, image_source = file, site_row.get('sourceUrl', 'biobalance.tn')
            elif (args.sources / f'bl-{key}.jpg').exists():
                image, image_source = args.sources / f'bl-{key}.jpg', f'https://www.barcodelookup.com/{key}'
        if image:
            shutil.copyfile(image, out / 'images' / f'{ean}.jpg')
        row['image'] = f'images/{ean}.jpg' if image else ''
        row['image_source'] = image_source
        missing = [label for label, ok in (('description', bool(row['description'])), ('photo', bool(image))) if not ok]
        row['status'] = 'complet' if not missing else 'à compléter : ' + ' + '.join(missing)
        row['notes'] = ' · '.join(row['notes'])
        rows.append(row)
    write(out, rows)


COLUMNS = [('ean', 'EAN'), ('reference', 'Référence interne'), ('designation', 'Désignation (liste BioBalance)'),
           ('name', 'Nom affiché'), ('range', 'Gamme'), ('category', 'Catégorie'), ('size', 'Contenance'),
           ('description', 'Description'), ('image', 'Image'), ('image_source', 'Source de l’image'),
           ('source_url', 'Source des données'), ('status', 'Statut'), ('notes', 'Remarques')]


def write(out, rows):
    (out / 'produits.json').write_text(json.dumps(rows, ensure_ascii=False, indent=1))
    with (out / 'produits.csv').open('w', newline='', encoding='utf-8-sig') as f:
        w = csv.writer(f, delimiter=';')
        w.writerow([label for _, label in COLUMNS])
        for r in rows:
            w.writerow([r[k] for k, _ in COLUMNS])
    wb = openpyxl.Workbook()
    sheet = wb.active
    sheet.title = 'Produits'
    sheet.append([label for _, label in COLUMNS])
    for r in rows:
        sheet.append([r[k] for k, _ in COLUMNS])
    for col, width in zip('ABCDEFGHIJKLM', (16, 22, 44, 48, 14, 18, 11, 70, 26, 36, 50, 22, 50)):
        sheet.column_dimensions[col].width = width
    sheet.freeze_panes = 'D2'
    wb.save(out / 'produits.xlsx')
    done = sum(r['status'] == 'complet' for r in rows)
    lines = [f'# Données initiales — {len(rows)} produits (les {len(rows)} codes-barres de votre liste)', '',
             f'- Complets (nom, description, photo) : **{done}**', f'- À compléter : {len(rows) - done}', '']
    lines += [f"- `{r['ean']}` {r['name']} — {r['status']}" for r in rows if r['status'] != 'complet']
    lines += ['', 'Aucun prix : BioBalance les fixe dans l’application (A, B, C).',
              'Les photos venant de Barcode Lookup sont celles de revendeurs : à remplacer par vos visuels officiels.']
    (out / 'RAPPORT.md').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    root = pathlib.Path(__file__).resolve().parents[2]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--workbook', type=pathlib.Path, required=True)
    ap.add_argument('--catalog', type=pathlib.Path, default=root / '.artifacts/catalog-operations-2026-09-22/catalog.json')
    ap.add_argument('--site-images', type=pathlib.Path, default=root / '.artifacts/catalog-operations-2026-09-22/images')
    ap.add_argument('--sources', type=pathlib.Path, default=root / 'data/initial-catalog/sources')
    ap.add_argument('--out', type=pathlib.Path, default=root / 'data/initial-catalog')
    run(ap.parse_args())
