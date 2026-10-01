#!/usr/bin/env python3
"""Read every product page of biobalance.tn (public pages, one request per page, 0.5 s apart)
into data/initial-catalog/sources/site-pages.json: title, intro, description tab, price-free."""
import json, pathlib, re, time
import requests
from bs4 import BeautifulSoup

ROOT = pathlib.Path(__file__).resolve().parents[2]
HEADERS = {'User-Agent': 'BioBalance-catalog/1.0', 'Accept-Language': 'fr'}
CATEGORIES = ['10-supercreams-', '17-serum', '26-nettoyants-visage', '33-tonique', '36-maquillage', '38-soins-capillaires', '46-soins-personnels']


def get(url, **params):
    time.sleep(0.5)
    return BeautifulSoup(requests.get(url, params=params, headers=HEADERS, timeout=30).text, 'lxml')


def product_urls():
    urls = set()
    for category in CATEGORIES:
        page = 1
        while True:
            soup = get(f'https://biobalance.tn/{category}', page=page)
            links = {a['href'] for a in soup.select('.product-miniature a[href$=".html"]')}
            urls |= links
            if not links or not soup.select_one('a.next, a[rel=next]'):
                break
            page += 1
    return sorted(urls)


def mapara():
    """Ingredient lists of the reseller's BioBalance pages: {url: {title, ingredients}}."""
    links = set()
    for page in range(1, 4):
        url = f'https://www.maparatunisie.tn/page/{page}/' if page > 1 else 'https://www.maparatunisie.tn/'
        soup = get(url, s='biobalance', post_type='product')
        found = {a['href'] for a in soup.select('a[href*="/produit/"]') if 'biobalance' in a['href'].lower()}
        links |= found
        if not found:
            break
    out = {}
    for url in sorted(links):
        soup = get(url)
        match = re.search(r'Ingr[ée]dients?\s*:\s*(.+?)(?:\sAvis\s|\sProduits similaires|$)', soup.get_text(' ', strip=True))
        out[url] = {'title': soup.select_one('h1').get_text(strip=True), 'ingredients': match[1][:1500] if match else ''}
    return out


MANUFACTURER = 'https://www.biobalance.com.tr'
FEATURES = ['ANIMAL FRIENDLY', 'COLOURANT FREE', 'DERMATOLOGICALLY TESTED', 'GLUTEN FREE', 'MINERAL OIL FREE', 'PERFUME FREE',
            'PETROLATUM FREE', 'PRESERVATIVE FREE', 'SILICONE FREE', 'VEGAN - NATURAL PRODUCT', 'ROOTED IN SCIENCE']


def manufacturer():
    """The manufacturer's own product pages: title, usage, ingredient list (INCI), formula claims."""
    from urllib.parse import urljoin
    urls = set()
    for listing in ('/urun-etiketi/all-products/', '/urun-kategori/hair-care/', '/urun-kategori/personal-care/'):
        try:
            soup = get(MANUFACTURER + listing)
        except requests.RequestException:
            continue
        urls |= {urljoin(MANUFACTURER, a['href']) for a in soup.select('a[href*="/urun/"]')}
    out = {}
    for url in sorted(urls):
        soup = get(url)
        title = soup.select_one('h1').get_text(strip=True) if soup.select_one('h1') else ''
        text = soup.get_text(' ', strip=True)
        body = text[text.find(title, text.find(title) + 1):] if text.count(title) > 1 else text
        # The real list follows the usage; "PROVEN EFFECTIVE INGREDIENTS:" is marketing copy.
        usage = re.search(r'(?:WHEN & )?HOW TO USE\s*:\s*(.+?)\s*(?<!EFFECTIVE )INGREDIENTS\s*:', body)
        inci = None
        if usage:
            inci = re.match(r'\s*(?<!EFFECTIVE )INGREDIENTS\s*:\s*(.+?)\s*(?:' + '|'.join(FEATURES) + r'|$)', body[usage.end() - len('INGREDIENTS:'):])
        out[url] = {'title': title, 'usage': usage[1].strip() if usage else '', 'ingredients': inci[1].strip(' .') if inci else '',
                    'claims': [f for f in FEATURES[:-1] if f in body]}
    return out


if __name__ == '__main__':
    import sys
    if '--manufacturer' in sys.argv:
        target = ROOT / 'data/initial-catalog/sources/manufacturer-pages.json'
        target.write_text(json.dumps(manufacturer(), ensure_ascii=False, indent=1))
        print('manufacturer ->', target)
        sys.exit()
    if '--mapara' in sys.argv:
        target = ROOT / 'data/initial-catalog/sources/mapara-ingredients.json'
        target.write_text(json.dumps(mapara(), ensure_ascii=False, indent=1))
        print('ingredients ->', target)
        sys.exit()
    pages = {}
    for url in product_urls():
        soup = get(url)
        info, description = soup.select_one('.product-information'), soup.select_one('#description')
        pages[url] = {'h1': soup.select_one('h1').get_text(strip=True),
                      'info': info.get_text(' ', strip=True) if info else '',
                      'desc': description.get_text(' ', strip=True) if description else ''}
    out = ROOT / 'data/initial-catalog/sources/site-pages.json'
    out.write_text(json.dumps(pages, ensure_ascii=False))
    print(len(pages), 'pages ->', out)
