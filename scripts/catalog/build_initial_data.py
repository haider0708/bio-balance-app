#!/usr/bin/env python3
"""Build BioBalance's clean product data from the official list of 39 barcodes.

Sources, in order of trust:
  1. the workbook the business keeps (EAN + designation): the list of record;
  2. biobalance.tn: each product page, read section by section (claim, benefits,
     usage, ingredients) and its photo;
  3. Barcode Lookup (scripts/catalog/barcode_fetch.py): ingredients, volume and a photo
     for the products the website does not carry.
Prices are deliberately left out: BioBalance sets them in the app.

Output (data/initial-catalog): produits.xlsx / .csv / .json, images/<EAN>.jpg, RAPPORT.md.
Nothing is invented: a field no source gives stays empty and is reported.
"""
import argparse, csv, json, pathlib, re, shutil
import openpyxl

CATEGORIES = {
    'maquillage': 'Maquillage', 'nettoyants-visage': 'Nettoyants visage', 'serum': 'Sérums',
    'soins-capillaires': 'Soins capillaires', 'soins-personnels': 'Soins personnels',
    'super-lift': 'Crèmes visage', 'supercreams-': 'Crèmes visage', 'tonique': 'Toniques',
}
# Names the website does not give (or gives badly). Facts only.
CURATED = {
    '8697711722011': dict(name='Eyelash Growth Serum', category='Soins du regard', size='6 ml', range='',
        description='Sérum pour cils et sourcils aux peptides (Biotinoyl Tripeptide-1), à la biotine et à l’acide hyaluronique.',
        benefits=['Soutient la pousse et le volume des cils et des sourcils', 'Hydrate et nourrit grâce à l’acide hyaluronique et au panthénol'],
        instructions='Retirer le maquillage et les résidus. Appliquer une fine ligne à la base des cils ou sur les sourcils, de préférence le soir (ou deux fois par jour). Utiliser chaque jour pendant au moins 30 jours. Éliminer les résidus d’huile démaquillante avant application.'),
    '8697711601514': dict(name='Hello Clean 3-in-1 Cleansing Balm Pure Vitamin C', category='Nettoyants visage', size='100 ml', range='Hello Clean',
        description='Baume nettoyant visage 3 en 1 à la vitamine C pure, pour peau terne. Sa texture sorbet se transforme en huile soyeuse au contact de la peau : il démaquille le maquillage waterproof, enlève la crème solaire et les impuretés.',
        benefits=['Illumine le teint (vitamine C pure, antioxydant)', 'Réduit les rougeurs', 'Laisse la peau douce et hydratée'],
        instructions='Prélever la quantité voulue avec la spatule fournie. Masser sur peau sèche en mouvements circulaires jusqu’à dissolution du maquillage et des impuretés, ajouter de l’eau tiède, masser à nouveau puis rincer. Yeux : garder la paupière fermée.',
        precautions='Usage externe uniquement. Tenir hors de portée des enfants. Conserver au frais, au sec, à l’abri du soleil.'),
    '8697711601538': dict(name='Hello Clean 3-in-1 Cleansing Balm Hyaluronic Acid', category='Nettoyants visage', size='100 ml', range='Hello Clean',
        description='Baume nettoyant visage 3 en 1 à l’acide hyaluronique (hyaluronate de sodium), pour peau normale à sèche. Sa texture sorbet se transforme en huile soyeuse au contact de la peau : il démaquille et nettoie en douceur.',
        benefits=['Hydrate intensément (acide hyaluronique)', 'Apaise grâce à l’extrait de fleur de Hoya Lacunosa', 'Laisse la peau douce et veloutée'],
        instructions='Prélever la quantité voulue avec la spatule fournie. Masser sur peau sèche en mouvements circulaires jusqu’à dissolution du maquillage et des impuretés, ajouter de l’eau tiède, masser à nouveau puis rincer. Yeux : garder la paupière fermée.',
        precautions='Usage externe uniquement. Tenir hors de portée des enfants. Conserver au frais, au sec, à l’abri du soleil.'),
    '8697711601521': dict(name='Hello Clean 3-in-1 Cleansing Balm Squalane', category='Nettoyants visage', size='100 ml', range='Hello Clean',
        description='Baume nettoyant visage 3 en 1 au squalane et au bisabolol, pour peau sensible ou à rougeurs. Sa texture sorbet se transforme en huile soyeuse au contact de la peau : il démaquille et nettoie sans agresser.',
        benefits=['Nourrit et protège (squalane, antioxydant naturel)', 'Répare et calme la peau sensible ou irritée (bisabolol)', 'Laisse la peau douce et hydratée'],
        instructions='Prélever la quantité voulue avec la spatule fournie. Masser sur peau sèche en mouvements circulaires jusqu’à dissolution du maquillage et des impuretés, ajouter de l’eau tiède, masser à nouveau puis rincer. Yeux : garder la paupière fermée.',
        precautions='Usage externe uniquement. Tenir hors de portée des enfants. Conserver au frais, au sec, à l’abri du soleil.'),
    '8697711601545': dict(name='Hello Clean 3-in-1 Cleansing Balm Oleanolic Acid', category='Nettoyants visage', size='100 ml', range='Hello Clean',
        description='Baume nettoyant visage 3 en 1 à l’acide oléanolique, pour peau grasse ou mixte. Sa texture sorbet se transforme en huile soyeuse au contact de la peau : il démaquille, nettoie et matifie.',
        benefits=['Contrôle l’excès de sébum', 'Minimise l’apparence des pores', 'Matifie et hydrate'],
        instructions='Prélever la quantité voulue avec la spatule fournie. Masser sur peau sèche en mouvements circulaires jusqu’à dissolution du maquillage et des impuretés, ajouter de l’eau tiède, masser à nouveau puis rincer. Yeux : garder la paupière fermée.',
        precautions='Usage externe uniquement. Tenir hors de portée des enfants. Conserver au frais, au sec, à l’abri du soleil.'),
    '8697711602139': dict(name='Night Recovery Super Serum Eye Contour', category='Sérums', size='20 ml', range='Super Serum',
        description='Super sérum contour des yeux au phyto-rétinol (bakuchiol), aux céramides et à l’acide hyaluronique : anti-rides et réparateur intense.',
        benefits=['Réduit les ridules et raffermit le contour des yeux (phyto-rétinol)', 'Renforce la barrière cutanée (céramide NP)', 'Hydrate et revitalise (acide hyaluronique)'],
        instructions='Appliquer une petite quantité sur peau propre et sèche et masser doucement autour des yeux, par mouvements circulaires, jusqu’à absorption, matin et soir.'),
    '8697711622410': dict(name='Dry & White Whitening Natural Roll-On Deodorant', category='Soins personnels', size='50 ml', range='Dry & White',
        description='Déodorant roll-on naturel éclaircissant : protection 48 h contre les mauvaises odeurs et aide à éclaircir la peau délicate des aisselles.',
        benefits=[], instructions=''),
    '8697711622427': dict(name='Déodorant Naturel Roll-On Anti-Repousse', category='Soins personnels', size='50 ml', range='Dry & Smooth'),
    '8697711600838': dict(name='Marine Collagen + Vitamin C Super Serum', category='Sérums', size='30 ml', range='Super Serum'),
    '8697711602115': dict(name='Advanced Night Recovery Super Serum', category='Sérums', size='30 ml', range='Super Serum'),
}
# The manufacturer's own page for each product (matched by hand on the official names).
MANUFACTURER_TITLE = {
    '8697711602016': 'SUPER PURE GEL CREAM MOISTURIZER 50 ML', '8697711602030': 'SUPER PLUMP CREAM MOISTURIZER 50 ML',
    '8697711602061': 'SUPER EYE CREAM MOISTURIZER 20 ML', '8697711602023': 'SUPER GLOW GEL CREAM MOISTURIZER 50 ML',
    '8697711602054': 'SUPER HYDRATOR CREAM MOISTURIZER 50 ML', '8697711602047': 'SUPER LIFT CREAM MOISTURIZER 50 ML',
    '8697711622427': 'DRY & SMOOTH HAIR THINNING NATURAL DEO ROLL-ON 50 ML',
    '8697711622434': 'DRY & SPORT FOR MEN NATURAL DEO ROLL-ON 50 ML',
    '8697711622410': 'DRY & WHITE WHITENING NATURAL DEO ROLL-ON 50 ML', '8697711740411': 'DRY & WHITE WHITENING NATURAL DEO ROLL-ON 50 ML',
    '8697711701009': 'DERMASEBUM PURIFYING FACIAL CLEANSING GEL 250 ML', '8697711701016': 'DERMASOOTHE SOOTHING FACIAL CLEANSING GEL 250 ML',
    '8697711621833': 'HELLO CLEAN CERAMIDE BOOSTER BI-PHASE MICELLAR WATER 500 ML',
    '8697711621819': 'HELLO CLEAN HYALURONIC HYDRATION MICELLAR WATER 500 ML',
    '8697711621826': 'HELLO CLEAN NIACINAMIDE CLARITY MICELLAR WATER 500 ML',
    '8697711722011': 'EYELASH GROWTH SERUM 6 ML',
    '8697711601514': 'HELLO CLEAN BRIGHTENING CLEANSING BALM 100 ML', '8697711601538': 'HELLO CLEAN DEEP HYDRATING CLEANSING BALM 100 ML',
    '8697711601521': 'HELLO CLEAN NOURISHING CLEANSING BALM 100 ML', '8697711601545': 'HELLO CLEAN PORE DOWNSIZER CLEANSING BALM 100 ML',
    '8697711600845': 'BETA SOLUTION SUPER SERUM 30 ML', '8697711602122': 'DEEP PEELING SUPER SERUM 30 ML',
    '8697711600838': 'COLLAGEN – VITAMIN C SUPER SERUM 30 ML', '8697711600814': 'DISCOLORATION FREE SUPER SERUM 30 ML',
    '8697711600777': 'HYALURONIC 3D SUPER SERUM 30 ML', '8697711600876': 'NIACINAMIDE-G SUPER SERUM 30 ML',
    '8697711600760': 'VITAMIN C SUPER SERUM 30 ML', '8697711600852': 'RETINOL’E SUPER SERUM 30 ML',
    '8697711600890': 'CAFFEINE SOLUTION %5 SUPER SERUM 30 ML', '8697711602313': 'GLOW SKIN C SUPER TONER 250 ML',
    '8697711602337': 'PORE TIGHT SUPER TONER 250 ML', '8697711700187': 'ORGANIC ALOE VERA SHAMPOO 330 ML',
    '8697711700170': 'ORGANIC CITRUS SHAMPOO 330 ML', '8697711700156': 'ORGANIC LAVENDER SHAMPOO 330 ML',
    '8697711700163': 'ORGANIC POMEGRANATE SHAMPOO 330 ML', '8697711700224': 'ORGANIC ARGAN OIL CONDITIONER 330 ML',
}
CLAIMS_FR = {'ANIMAL FRIENDLY': 'respectueux des animaux', 'COLOURANT FREE': 'sans colorant', 'DERMATOLOGICALLY TESTED': 'testé dermatologiquement',
             'GLUTEN FREE': 'sans gluten', 'MINERAL OIL FREE': 'sans huile minérale', 'PERFUME FREE': 'sans parfum',
             'PETROLATUM FREE': 'sans pétrolatum', 'PRESERVATIVE FREE': 'sans conservateur', 'SILICONE FREE': 'sans silicone',
             'VEGAN - NATURAL PRODUCT': 'vegan, d’origine naturelle'}
# French usage where the Tunisian site has none (translated from the manufacturer's English).
USAGE_FR = {
    'DEO': 'Agiter avant emploi pour activer la formule. Appliquer sur des aisselles propres et sèches.',
    '8697711602115': 'Appliquer une petite quantité de sérum sur le visage propre et sec, matin et soir, et masser par mouvements circulaires doux jusqu’à absorption.',
    '8697711600838': 'Appliquer directement sur le visage nettoyé, matin et soir. Laisser le sérum pénétrer avant d’appliquer la crème hydratante.',
}
SMALL = {'and', 'de', 'of', 'with', 'for', 'the', 'à', 'et', 'pour', 'au', 'aux', 'du', 'en'}
KEEP = {'AH', 'BHA', 'AHA', 'SPF', 'EGCG', 'PHA', 'UV', 'TND', 'HC', 'II'}
RANGES = [('super serum', 'Super Serum'), ('super toner', 'Super Toner'), ('cream moisturizer', 'Super Cream'),
          ('super hydrator', 'Super Cream'), ('hello clean', 'Hello Clean'), ('dermasebum', 'Dermasebum'),
          ('dermasoothe', 'Dermasoothe'), ('dry & white', 'Dry & White'), ('dry & sport', 'Dry & Sport'),
          ('organic', 'Organic'), ('magic touch', 'Magic Touch')]
LABELS = r'(Avantages|Conseils? d[’\']utilisation|Mode d[’\']emploi|Ingr[ée]dients?|Composition|Pr[ée]cautions?)'


def clean(text):
    return re.sub(r'\s+', ' ', (text or '').replace('\xa0', ' ').replace('EXTRAit', 'Extrait')).strip()


def title_case(text):
    words = []
    for index, word in enumerate(clean(text).split(' ')):
        bare = re.sub(r'[^\w]', '', word)
        if bare.upper() in KEEP or any(c.isdigit() for c in bare):
            words.append(word.upper() if bare.upper() in KEEP else word)
        elif word.isupper() or word.islower() or index == 0:
            lowered = word.lower()
            words.append(lowered if lowered in SMALL and index else '-'.join(p.capitalize() for p in lowered.split('-')))
        else:
            words.append(word)
    return ' '.join(words)


def size_of(*texts):
    match = re.search(r'\b(\d+(?:[.,]\d+)?)\s*(ml|g)\b', ' '.join(texts), re.I)
    return f'{match[1].replace(",", ".")} {match[2].lower()}' if match else ''


def sentence_case(text):
    """An all-caps tagline in sentence case, keeping acronyms and one-letter names (vitamine C, B5)."""
    words = []
    for word in text.lower().split(' '):
        bare = re.sub(r'[^\w]', '', word)
        words.append(word.upper() if bare.upper() in KEEP or re.fullmatch(r'[a-z]\d?', bare) and len(bare) <= 2 and bare not in ('à', 'a', 'd', 'l', 'de') else word)
    out = ' '.join(words)
    return out[:1].upper() + out[1:]


def tidy_intro(text):
    """The website's lead line starts with a tagline, then the volume, then the story:
    keep the tagline as a sentence and drop the volume (it has its own field)."""
    match = re.search(r'\s*\b\d+(?:[.,]\d+)?\s*(?:ml|g)\b\s*', text)
    if not match or match.start() > 140:
        return text
    before, after = text[:match.start()].strip(' .:–-'), text[match.end():].strip()
    before = re.sub(r'^\d+(?=[A-ZÉÈ])', '', before)
    letters = [c for c in before if c.isalpha()]
    if letters and sum(c.isupper() for c in letters) / len(letters) > 0.6:
        before = sentence_case(before)
    return (before + '. ' if before else '') + (after[:1].upper() + after[1:])


def sections(description):
    """The website's description tab, split on its labels."""
    parts = re.split(LABELS + r'\s*:?', clean(description))
    found, key = {}, None
    for part in parts[1:]:
        if re.fullmatch(LABELS, part.strip()):
            key = part.strip().lower()
        elif key:
            found[key] = clean(part)
    return found


def read_site_page(page):
    info = clean(page['info']).split(' Quantité')[0]
    info = re.sub(r'\s*TEST[ÉE]E? DERMATOLOGIQUEMENT\s*', ' ', info, flags=re.I)
    found = sections(page['desc'])
    benefits = [clean(b) for b in re.split(r'•', found.get('avantages', '')) if clean(b)]
    usage = next((v for k, v in found.items() if k.startswith(('conseil', 'mode'))), '')
    ingredients = next((v for k, v in found.items() if k.startswith(('ingr', 'composition'))), '')
    return dict(intro=tidy_intro(clean(info)), benefits=benefits, instructions=usage, ingredients=ingredients,
                precautions=found.get('précautions') or found.get('precautions') or '')


INCI = re.compile(r'(?:Ingrediente|Ingredients|INGREDIENTS|Ingrédients|Състав)\s*:\s*(.+?)(?=\s\.\s|\s\.$|https?://|$)', re.S)


def inci(text):
    """An INCI list is the same in every language: keep a candidate only when it reads as one
    (many Latin names, mostly capitalised, separated by commas)."""
    best = ''
    for match in INCI.finditer(text or ''):
        candidate = match[1].strip(' .;')
        tokens = [t.strip() for t in candidate.split(',') if t.strip()]
        if len(tokens) >= 6 and sum(bool(re.match(r'[A-Z0-9]', t)) for t in tokens) / len(tokens) >= 0.9 and len(candidate) > len(best):
            best = candidate
    return best


def run(args):
    ws = openpyxl.load_workbook(args.workbook)['Feuil1']
    listed = [(str(r[0]), clean(r[1])) for r in ws.iter_rows(min_row=6, values_only=True) if r[0]]
    catalog = {p['barcode']: p for p in json.loads(args.catalog.read_text())['products'] if p.get('barcode')}
    pages = json.loads(args.site_pages.read_text())
    maker = {v['title']: v for v in json.loads(args.manufacturer.read_text()).values()}
    by_url = {u: read_site_page(p) | {'title': p['h1']} for u, p in pages.items()}
    capture = json.loads(args.capture.read_text())['products']
    same_as = {'8697711622410': '8697711740411'}
    # The reseller's page for the same product (matched by hand) gives an ingredient list only
    # where neither the website nor Barcode Lookup does.
    mapara = {u.rstrip('/').split('/')[-1]: v['ingredients'] for u, v in json.loads(args.mapara.read_text()).items() if v['ingredients']}
    mapara_slug = {'8697711622434': 'biobalance-dry-sport-roll-on-natural-for-men-48h-50ml',
                   '8697711622410': 'biobalance-dry-white-roll-on-eclaircissant-48h-50ml',
                   '8697711740411': 'biobalance-dry-white-roll-on-eclaircissant-48h-50ml',
                   '8697711600838': 'biobalance-serum-collagene-marin-vitamine-c-30ml',
                   '8697711602023': 'biobalance-super-glow-50ml', '8697711602054': 'biobalance-super-hydrator-50ml',
                   '8697711602030': 'biobalance-super-plump-50ml', '8697711602016': 'biobalance-super-pure-50ml',
                   '8697711600845': 'biobalance-super-serum-acide-salicylique-pur-2-30ml'}
    (args.out / 'images').mkdir(parents=True, exist_ok=True)
    rows = []
    for ean, designation in listed:
        own = catalog.get(ean)
        sibling = catalog.get(same_as.get(ean, ''))
        curated = CURATED.get(ean, {})
        # A code whose own page is empty falls back on its sibling code (same product).
        source = sibling if ean in same_as else own
        url = (source or {}).get('sourceUrl') or ''
        site = by_url.get(url, {})
        bl = capture.get(ean, {})
        name = curated.get('name') or re.sub(r'\s*\b\d+\s*ml\b', '', title_case(site.get('title') or designation), flags=re.I).strip()
        category = curated.get('category') or next((v for k, v in CATEGORIES.items() if f'/{k}/' in url), '')
        official = maker.get(MANUFACTURER_TITLE.get(ean, ''), {})
        size = curated.get('size') or size_of(site.get('intro', ''), site.get('title', ''), designation, bl.get('title', ''), official.get('title', ''))
        rng = curated.get('range') if 'range' in curated else next((r for k, r in RANGES if k in f'{name} {site.get("title", "")}'.lower()), '')
        rng = rng or ('Super Cream' if 'supercreams' in (url or '') else '')
        intro = curated.get('description') or site.get('intro') or clean((source or {}).get('description', ''))
        benefits = curated.get('benefits') or site.get('benefits', [])
        claims = [CLAIMS_FR[c] for c in official.get('claims', []) if c in CLAIMS_FR]
        description = intro + (('\n\nAvantages :\n' + '\n'.join(f'• {b}' for b in benefits)) if benefits else '')
        if claims:
            description += '\n\nFormule : ' + ', '.join(claims) + '.'
        instructions = (curated.get('instructions') or site.get('instructions', '')
                        or USAGE_FR.get(ean) or (USAGE_FR['DEO'] if 'DEO ROLL-ON' in MANUFACTURER_TITLE.get(ean, '') else ''))
        ingredients = (official.get('ingredients') or site.get('ingredients') or inci(bl.get('description'))
                       or mapara.get(mapara_slug.get(ean, ''), ''))
        precautions = curated.get('precautions') or site.get('precautions', '')
        image = None
        for key in (ean, same_as.get(ean)):
            row = catalog.get(key or '')
            file = row and row.get('imageFile') and args.site_images / pathlib.Path(row['imageFile']).name
            if image is None and file and file.exists():
                image, image_source = file, row.get('sourceUrl', '')
        if image is None and (args.sources / f'bl-{ean}.jpg').exists():
            image, image_source = args.sources / f'bl-{ean}.jpg', f'https://www.barcodelookup.com/{ean}'
        if image:
            shutil.copyfile(image, args.out / 'images' / f'{ean}.jpg')
        sources = [u for u in (url, f'https://www.barcodelookup.com/{ean}' if bl else '') if u]
        record = dict(ean=ean, reference=(own or {}).get('reference') or f'BB-EAN-{ean}', designation=designation,
                      name=name, range=rng, category=category, size=size, description=description,
                      instructions=instructions, ingredients=ingredients, precautions=precautions,
                      image=f'images/{ean}.jpg' if image else '', image_source=image_source if image else '',
                      sources=' | '.join(sources))
        gaps = [label for label, ok in (('description', intro), ('catégorie', category), ('contenance', size), ('mode d’emploi', instructions),
                                        ('ingrédients', ingredients), ('photo', image)) if not ok]
        record['missing'] = ', '.join(gaps)
        rows.append(record)
    write(args.out, rows)


COLUMNS = [('ean', 'EAN'), ('reference', 'Référence interne'), ('designation', 'Désignation (liste BioBalance)'), ('name', 'Nom'),
           ('range', 'Gamme'), ('category', 'Catégorie'), ('size', 'Contenance'), ('description', 'Description'),
           ('instructions', 'Conseils d’utilisation'), ('ingredients', 'Ingrédients'), ('precautions', 'Précautions'),
           ('image', 'Image'), ('image_source', 'Source de l’image'), ('sources', 'Sources'), ('missing', 'Champs manquants')]


def write(out, rows):
    (out / 'produits.json').write_text(json.dumps(rows, ensure_ascii=False, indent=1))
    with (out / 'produits.csv').open('w', newline='', encoding='utf-8-sig') as f:
        writer = csv.writer(f, delimiter=';')
        writer.writerow([label for _, label in COLUMNS])
        writer.writerows([[r[k] for k, _ in COLUMNS] for r in rows])
    wb = openpyxl.Workbook()
    sheet = wb.active
    sheet.title = 'Produits'
    sheet.append([label for _, label in COLUMNS])
    for r in rows:
        sheet.append([r[k] for k, _ in COLUMNS])
    for col, width in zip('ABCDEFGHIJKLMNO', (16, 22, 40, 44, 14, 18, 11, 70, 60, 60, 40, 26, 36, 60, 24)):
        sheet.column_dimensions[col].width = width
    sheet.freeze_panes = 'E2'
    wb.save(out / 'produits.xlsx')
    total = len(rows)
    field = lambda k: sum(bool(r[k]) for r in rows)
    lines = [f'# Données initiales — {total} produits (les {total} codes-barres de votre liste)', '',
             '| Champ | Renseigné |', '|---|---|']
    lines += [f'| {label} | {field(k)}/{total} |' for k, label in
              (('name', 'Nom'), ('category', 'Catégorie'), ('range', 'Gamme'), ('size', 'Contenance'), ('description', 'Description'),
               ('instructions', 'Conseils d’utilisation'), ('ingredients', 'Ingrédients'), ('precautions', 'Précautions'), ('image', 'Photo'))]
    lines += ['', 'Aucun prix : BioBalance les fixe dans l’application (A, B, C). Une gamme vide est normale pour un produit hors gamme.', '']
    lines += [f"- `{r['ean']}` {r['name']} — manque : {r['missing']}" for r in rows if r['missing']]
    (out / 'RAPPORT.md').write_text('\n'.join(lines) + '\n')
    print('\n'.join(lines))


if __name__ == '__main__':
    root = pathlib.Path(__file__).resolve().parents[2]
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--workbook', type=pathlib.Path, required=True)
    ap.add_argument('--catalog', type=pathlib.Path, default=root / 'data/initial-catalog/sources/site-catalog.json')
    ap.add_argument('--site-pages', type=pathlib.Path, default=root / 'data/initial-catalog/sources/site-pages.json')
    ap.add_argument('--site-images', type=pathlib.Path, default=root / 'data/initial-catalog/sources/site-images')
    ap.add_argument('--sources', type=pathlib.Path, default=root / 'data/initial-catalog/sources')
    ap.add_argument('--capture', type=pathlib.Path, default=root / 'data/initial-catalog/sources/barcodelookup-capture.json')
    ap.add_argument('--manufacturer', type=pathlib.Path, default=root / 'data/initial-catalog/sources/manufacturer-pages.json')
    ap.add_argument('--mapara', type=pathlib.Path, default=root / 'data/initial-catalog/sources/mapara-ingredients.json')
    ap.add_argument('--out', type=pathlib.Path, default=root / 'data/initial-catalog')
    run(ap.parse_args())
