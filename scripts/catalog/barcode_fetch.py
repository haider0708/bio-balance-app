#!/usr/bin/env python3
"""Look products up on barcodelookup.com from their barcode, the way a person does.

A real browser window (Brave) opens on a fresh, empty profile — never your own
sessions — and visits one product page at a time, at a human pace. The page is
read like a reader would read it: title, brand, description, photo.

What this tool does NOT do, on purpose:
  * it does not hide that it is automated, solve a verification, or reuse cookies;
    if the site asks for a verification, the window stays open, you complete it
    yourself, and the tool carries on;
  * it does not run in parallel or hammer the site: a few seconds to a few tens of
    seconds between two pages, 20 products per run by default.

Usage:
  python3 scripts/catalog/barcode_fetch.py 8697711722011 8697711601514
  python3 scripts/catalog/barcode_fetch.py --missing        # codes whose data is incomplete

Needs:  pip install playwright   (no browser download: it drives the installed Brave)
Result: data/initial-catalog/sources/barcodelookup-capture.json and bl-<EAN>.jpg,
        then `python3 scripts/catalog/build_initial_data.py --workbook <xlsx>` rebuilds the data.
"""
import argparse, json, pathlib, random, re, shutil, subprocess, sys, tempfile, time
import requests

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCES = ROOT / 'data/initial-catalog/sources'
CAPTURE = SOURCES / 'barcodelookup-capture.json'
BROWSERS = ['/snap/bin/brave', 'brave-browser', 'brave', 'google-chrome', 'chromium', 'chromium-browser']
PORT = 9333
EXTRACT = """() => {
  const text = document.body.innerText;
  const title = document.querySelector('h4')?.innerText ?? null;
  const description = text.includes('Description:') ? text.split('Description:')[1].split('Product Reviews')[0].trim() : null;
  const image = [...document.images].map((i) => i.src).find((s) => s.includes('images.barcodelookup.com')) ?? null;
  return { title, brand: (text.match(/Brand:\\s*(.*)/) || [])[1] ?? null, description, image,
           notFound: /not found|no results|could not find/i.test(document.title + ' ' + text.slice(0, 600)) };
}"""


def valid_ean(code):
    return code.isdigit() and len(code) == 13 and sum(int(c) * (1 if i % 2 == 0 else 3) for i, c in enumerate(code)) % 10 == 0


def find_browser():
    path = next((b for b in BROWSERS if shutil.which(b)), None)
    if not path:
        sys.exit('Brave ou Chrome introuvable.')
    return shutil.which(path)


def challenged(page):
    title = (page.title() or '').lower()
    return 'verification' in title or 'just a moment' in title or page.query_selector('iframe[src*="captcha"], iframe[src*="challenge"]') is not None


def wait_for_person(page, patience=300):
    """A verification is for a person: wait, never solve."""
    print('  ! Le site demande une vérification. Faites-la dans la fenêtre : le script attend.', flush=True)
    deadline = time.time() + patience
    while challenged(page):
        if time.time() > deadline:
            return False
        time.sleep(2)
    return True


def lookup(page, ean):
    page.goto(f'https://www.barcodelookup.com/{ean}', wait_until='domcontentloaded', timeout=60000)
    time.sleep(random.uniform(2.5, 5))
    if challenged(page) and not wait_for_person(page):
        return None
    # Read the page the way a reader does: a pause, then a scroll to the description.
    page.mouse.wheel(0, random.randint(300, 700))
    time.sleep(random.uniform(1.5, 3.5))
    return page.evaluate(EXTRACT)


def save_image(ean, url):
    reply = requests.get(url, headers={'User-Agent': 'BioBalance-catalog/1.0'}, timeout=30)
    if reply.ok and reply.headers.get('content-type', '').startswith('image'):
        SOURCES.mkdir(parents=True, exist_ok=True)
        (SOURCES / f'bl-{ean}.jpg').write_bytes(reply.content)
        return True
    return False


def missing_codes():
    data = json.loads((ROOT / 'data/initial-catalog/produits.json').read_text())
    return [r['ean'] for r in data if r['status'] != 'complet']


def run(args):
    from playwright.sync_api import sync_playwright
    codes = args.codes or (missing_codes() if args.missing else [])
    bad = [c for c in codes if not valid_ean(c)]
    if bad:
        sys.exit(f'Codes-barres invalides : {", ".join(bad)}')
    if not codes:
        sys.exit('Aucun code à chercher.')
    codes = list(dict.fromkeys(codes))[: args.limit]
    capture = json.loads(args.out.read_text()) if args.out.exists() else {'source': 'https://www.barcodelookup.com/<EAN>', 'products': {}}
    profile = tempfile.mkdtemp(prefix='barcode-fetch-', dir=pathlib.Path.home())
    browser = subprocess.Popen([find_browser(), f'--remote-debugging-port={PORT}', f'--user-data-dir={profile}',
                                '--no-first-run', '--no-default-browser-check', 'about:blank'],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        with sync_playwright() as pw:
            for _ in range(40):
                try:
                    connection = pw.chromium.connect_over_cdp(f'http://127.0.0.1:{PORT}')
                    break
                except Exception:
                    time.sleep(1)
            else:
                sys.exit('Le navigateur ne répond pas.')
            page = connection.contexts[0].pages[0] if connection.contexts[0].pages else connection.contexts[0].new_page()
            found = 0
            for index, ean in enumerate(codes):
                print(f'[{index + 1}/{len(codes)}] {ean}', flush=True)
                try:
                    info = lookup(page, ean)
                except Exception as error:
                    print(f'  ! échec : {error}')
                    continue
                if info is None or info['notFound'] or not info['title']:
                    print('  — pas de fiche' if info else '  — vérification non faite, arrêt')
                    if info is None:
                        break
                else:
                    image = bool(info['image']) and save_image(ean, info['image'])
                    capture['products'][ean] = {'title': info['title'], 'brand': info['brand'], 'image': info['image'],
                                                'description': (info['description'] or '')[:8000]}
                    print(f"  ✓ {info['title'][:70]} | photo : {'oui' if image else 'non'}")
                    found += 1
                    capture['capturedAt'] = time.strftime('%Y-%m-%d')
                    args.out.parent.mkdir(parents=True, exist_ok=True)
                    args.out.write_text(json.dumps(capture, ensure_ascii=False, indent=2))
                if index < len(codes) - 1:
                    time.sleep(random.uniform(args.min_delay, args.max_delay))
            print(f'{found}/{len(codes)} fiches relevées -> {args.out}')
            # A snap-installed Brave cannot be stopped from outside: ask it to close.
            try:
                connection.new_browser_cdp_session().send('Browser.close')
            except Exception:
                pass
    finally:
        try:
            browser.wait(timeout=10)
        except Exception:
            try:
                browser.terminate()
            except OSError:
                pass
        shutil.rmtree(profile, ignore_errors=True)


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('codes', nargs='*', help='EAN-13 à chercher')
    ap.add_argument('--missing', action='store_true', help='chercher les codes dont les données sont incomplètes')
    ap.add_argument('--limit', type=int, default=20, help='nombre maximal de produits par passage')
    ap.add_argument('--min-delay', type=float, default=8)
    ap.add_argument('--max-delay', type=float, default=20)
    ap.add_argument('--out', type=pathlib.Path, default=CAPTURE)
    run(ap.parse_args())
