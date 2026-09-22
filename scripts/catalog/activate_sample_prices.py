#!/usr/bin/env python3
"""Activate explicitly reviewed sample prices without altering the first import.

Only previously inactive, unpriced references may be amended. Price provenance
is visible in the catalog name and description. Opening movements use durable
operation identifiers, and all changes use the ordinary authenticated APIs.
"""
import argparse
import datetime
import hashlib
import json
import pathlib
import time
import uuid

from operator_client import Client, save_json


def validate_samples(original, amendments, root):
    if amendments.get('schemaVersion') != 1:
        raise ValueError('Unsupported amendment schema')
    originals = {p['reference']: p for p in original['products']}
    samples = amendments['products']
    if not 1 <= len(samples) <= 20:
        raise ValueError('Sample amendment limit')
    seen = set()
    for sample in samples:
        reference = sample['reference']
        previous = originals.get(reference)
        if reference in seen or not previous or previous['active'] or previous['priceMillimes'] is not None:
            raise ValueError('Only unique, previously unpriced inactive products may be amended')
        seen.add(reference)
        price = sample.get('priceMillimes')
        if sample.get('priceKind') != 'sample' or not isinstance(price, str) or not price.isascii() or not price.isdigit() or not 0 < int(price) <= 10000000:
            raise ValueError('Explicit positive sample price in millimes required')
        image = root / sample['imageFile']
        if image.is_symlink() or not image.resolve().is_relative_to(root.resolve()) or image.stat().st_size > 10 * 1024 * 1024:
            raise ValueError('Invalid reviewed image')
        if hashlib.sha256(image.read_bytes()).hexdigest() != sample['imageSha256']:
            raise ValueError('Reviewed image changed')
    return originals, samples


def product_fields(previous, sample):
    price = int(sample['priceMillimes'])
    amount = f'{price // 1000},{price % 1000:03d}'
    return {
        'reference': previous['reference'],
        'barcode': previous['barcode'],
        'name': previous['name'] + ' — prix démo',
        'description': (
            f'PRIX DE DÉMONSTRATION : {amount} TND. Tarif provisoire fictif, '
            'à remplacer avant utilisation commerciale. '
            + previous['description']
        ),
        'active': True,
    }


def recoverable_product(current, previous, desired, imported):
    if current['id'] != imported['id']:
        raise ValueError('Catalog identity changed')
    if all(current.get(k) == v for k, v in desired.items()):
        return True
    old_fields = {k: previous[k] for k in ('reference', 'barcode', 'name', 'description', 'active')}
    if current['version'] != imported['version'] or current.get('imageId') is not None or any(current.get(k) != v for k, v in old_fields.items()):
        raise ValueError('Catalog was edited after import; review required')
    return False


def upload_image(client, sample, root):
    content = (root / sample['imageFile']).read_bytes()
    if not content.startswith(b'\xff\xd8'):
        raise ValueError('Reviewed JPEG required')
    asset = client.call('POST', '/v1/media/uploads', {
        'purpose': 'catalog', 'fileName': sample['reference'] + '-sample.jpg',
        'mime': 'image/jpeg', 'size': len(content), 'sha256': sample['imageSha256'],
    }, expected=201)
    route = '/v1/media/uploads/' + asset['id']
    status = client.call('GET', route)
    while status['status'] == 'uploading' and int(status['received']) < len(content):
        offset = int(status['received'])
        client.call('PUT', route, content[offset:offset + 512 * 1024], headers={
            'Content-Type': 'application/octet-stream', 'Upload-Offset': str(offset),
        })
        status = client.call('GET', route)
    deadline = time.monotonic() + 180
    while status['status'] != 'ready' and time.monotonic() < deadline:
        if status['status'] not in {'uploading', 'processing'}:
            raise ValueError('Media processing failed')
        time.sleep(1)
        status = client.call('GET', route)
    if status['status'] != 'ready':
        raise ValueError('Media processing timeout')
    meta = client.call('GET', '/v1/media/' + asset['id'] + '/metadata')
    processed = client.call('GET', '/v1/media/' + asset['id'], raw=True)
    if len(processed) != int(meta['size']) or hashlib.sha256(processed).hexdigest() != meta['sha256']:
        raise ValueError('Processed image integrity mismatch')
    return asset['id'], meta


def run(args):
    root = args.directory.resolve()
    catalog_file = root / 'catalog.json'
    original = json.loads(catalog_file.read_text())
    amendments = json.loads(args.amendments.read_text())
    originals, samples = validate_samples(original, amendments, args.amendments.parent.resolve())
    imported = json.loads((root / 'import-state.json').read_text())
    original_hash = hashlib.sha256(catalog_file.read_bytes()).hexdigest()
    if imported['manifestSha256'] != original_hash or imported['api'] != args.base_url:
        raise ValueError('Original import scope mismatch')
    if not args.apply:
        print(json.dumps({'reviewedSamplePrices': len(samples), 'apply': False}))
        return
    stores = json.loads((root / 'stores-created.json').read_text())
    manifest = json.loads((root / 'demo-private.json').read_text())
    if manifest['dataset'] != 'biobalance-demo-2026-09' or len(stores) != 5 or any(not s['name'].startswith('DÉMO — ') for s in stores):
        raise ValueError('Dedicated demo stores required')
    state_file = root / 'sample-price-state.json'
    binding = {'api': args.base_url, 'originalSha256': original_hash,
               'amendmentSha256': hashlib.sha256(args.amendments.read_bytes()).hexdigest(),
               'actorId': imported['actorId']}
    state = json.loads(state_file.read_text()) if state_file.exists() else {
        **binding, 'products': {}, 'stores': {},
        'date': datetime.datetime.now(datetime.timezone.utc).date().isoformat(),
    }
    if any(state.get(k) != v for k, v in binding.items()):
        raise ValueError('Amendment checkpoint scope mismatch')

    def save():
        save_json(state_file, state)

    def route(store, suffix):
        return '/v1/stores/' + store['id'] + suffix + '?organizationId=' + store['organizationId']

    clients = []
    try:
        admin = Client(args.base_url, json.loads(args.admin_file.read_text()), root)
        clients.append(admin)
        actor = admin.call('GET', '/v1/identity/me')
        if not actor['platformAdmin'] or actor['id'] != imported['actorId']:
            raise ValueError('Original administrator required')
        products = admin.call('GET', route(stores[0], '/collections/products'))
        current_by_ref = {p['reference']: p for p in products}
        for sample in samples:
            reference = sample['reference']
            current = current_by_ref[reference]
            desired = product_fields(originals[reference], sample)
            recovered = recoverable_product(current, originals[reference], desired, imported['products'][reference])
            image_id, meta = upload_image(admin, sample, args.amendments.parent)
            if recovered:
                if current['imageId'] != image_id:
                    raise ValueError('Accepted product image changed')
            else:
                payload = {**desired, 'imageId': image_id, 'id': current['id'], 'expectedVersion': current['version']}
                entry = state['products'].setdefault(reference, {'payload': payload})
                if entry['payload'] != payload:
                    raise ValueError('Uncertain catalog submission changed')
                save()
                current = admin.call('POST', '/v1/catalog/products', payload, expected=201)
            state['products'].setdefault(reference, {}).update({
                'id': current['id'], 'version': current['version'], 'imageId': image_id,
                'processedSha256': meta['sha256'], 'processedBytes': int(meta['size']), 'complete': True,
            })
            save()
            print('Sample price and image verified:', reference, flush=True)

        owners = {}
        for store in stores:
            organization = store['organizationId']
            if organization not in owners:
                credentials = next(u for u in manifest['users'] if u['organizationId'] == organization and u['owner'])
                manager = Client(args.base_url, credentials, root)
                clients.append(manager)
                owners[organization] = (manager, manager.call('GET', '/v1/identity/me')['id'])
            manager, manager_id = owners[organization]
            configs = {c['productId']: c for c in manager.call('GET', route(store, '/collections/config'))}
            entry = state['stores'].setdefault(store['id'], {'actorId': manager_id})
            if entry['actorId'] != manager_id:
                raise ValueError('Opening command account changed')
            lines = []
            expiry = (datetime.date.fromisoformat(state['date']) + datetime.timedelta(days=540)).isoformat()
            for index, sample in enumerate(samples):
                product_id = state['products'][sample['reference']]['id']
                wanted = {'priceMillimes': sample['priceMillimes'], 'threshold': 5, 'pointsPerUnit': 5}
                old = configs.get(product_id)
                if old:
                    if any(str(old[k]) != str(v) for k, v in wanted.items()):
                        raise ValueError('Existing demo price configuration changed')
                else:
                    manager.call('PATCH', route(store, '/products/' + product_id), wanted)
                lines.append({'productId': product_id, 'batch': 'DEMO-SAMPLE-' + store['slug'].upper() + '-' + str(index + 1),
                              'expiry': expiry, 'quantity': 15 + index})
            if 'operation' not in entry:
                entry['operation'] = {
                    'operationId': str(uuid.uuid4()), 'organizationId': organization, 'storeId': store['id'],
                    'payloadVersion': 2, 'dependencies': [],
                    'command': {'type': 'stock.receive', 'reason': 'opening', 'lines': lines},
                }
                entry['announcementId'] = str(uuid.uuid4())
                save()
            result = manager.call('POST', '/v1/sync/push', {'operations': [entry['operation']]}, expected=201)['results'][0]
            if result['status'] != 'accepted' or (entry.get('result') and entry['result'] != result):
                raise ValueError('Opening command failed or idempotency result changed')
            entry['result'] = result
            save()
            manager.call('POST', route(store, '/announcements'), {
                'id': entry['announcementId'], 'title': 'Sept tarifs provisoires pour la démonstration',
                'body': 'Les produits marqués « prix démo » utilisent un tarif fictif en TND. Leurs stocks, lots et dates sont simulés. Remplacez ces tarifs avant toute utilisation commerciale.',
                'audience': 'salespeople',
            }, expected=201)
            entry['complete'] = True
            save()
            print('Sample stock verified:', store['slug'], flush=True)
        print(json.dumps({'sampleProducts': len(samples), 'stores': len(stores), 'openingOperations': len(state['stores'])}))
    finally:
        for client in reversed(clients):
            try:
                client.close()
            except Exception:
                pass


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--directory', type=pathlib.Path, required=True)
    parser.add_argument('--amendments', type=pathlib.Path, required=True)
    parser.add_argument('--admin-file', type=pathlib.Path, required=True)
    parser.add_argument('--base-url', required=True)
    parser.add_argument('--apply', action='store_true')
    run(parser.parse_args())
