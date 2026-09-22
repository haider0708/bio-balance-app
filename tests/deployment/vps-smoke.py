#!/usr/bin/env python3
"""Explicit operator smoke check; creates two unpublished media assets, no sales/stores.

Run on the VPS with its private administrator setup and qualification fixtures.
Credentials and tokens are never printed. A small state file preserves asset IDs.
"""
import argparse
import base64
import hashlib
import hmac
import json
import pathlib
import struct
import time
import urllib.error
import urllib.parse
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--base-url', required=True)
parser.add_argument('--directory', required=True, type=pathlib.Path)
parser.add_argument('--admin-file', required=True, type=pathlib.Path)
parser.add_argument('--allow-create-media', action='store_true', required=True)
args = parser.parse_args()
origin = urllib.parse.urlsplit(args.base_url)
assert origin.scheme == 'https' or (origin.scheme == 'http' and origin.hostname in {'127.0.0.1', 'localhost'})
assert not origin.username and not origin.query and not origin.fragment
admin = json.loads(args.admin_file.read_text())
token = None


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, url):
        return None


opener = urllib.request.build_opener(NoRedirect())


def call(method, route, data=None, *, expected=200, headers=None):
    # Identify the operator tool honestly; Cloudflare may reject generic urllib.
    outgoing = {'User-Agent': 'BioBalance-Deployment/1.0', **(headers or {})}
    if token:
        outgoing['Authorization'] = 'Bearer ' + token
    if isinstance(data, dict):
        data = json.dumps(data).encode()
        outgoing['Content-Type'] = 'application/json'
    request = urllib.request.Request(args.base_url + route, data=data, headers=outgoing, method=method)
    try:
        response = opener.open(request, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.status == expected, f'{method} {route.split("?")[0]}: HTTP {response.status}, expected {expected}'
        if 'application/json' in response.headers.get('Content-Type', ''):
            body = json.loads(body)
        return body, response.headers


assert call('GET', '/health')[0]['status'] == 'ok'
call('GET', '/v1/stores', expected=401)
call('GET', '/docs', expected=404)
call('GET', '/_media/qualification.png', expected=404)
params = urllib.parse.parse_qs(urllib.parse.urlsplit(admin['totpUri']).query)
period = int(params.get('period', ['30'])[0])
step_file = args.directory / 'last-login-step'
previous = int(step_file.read_text()) if step_file.exists() else -1
delay = (previous + 1) * period - time.time() + 0.2
assert delay <= period + 1, 'Unexpected administrator login clock'
if delay > 0:
    time.sleep(delay)
step = int(time.time() // period)
key = params['secret'][0]
secret = base64.b32decode(key + '=' * (-len(key) % 8))
digest = hmac.new(secret, struct.pack('>Q', step), hashlib.sha1).digest()
offset = digest[-1] & 15
otp = str((struct.unpack('>I', digest[offset:offset + 4])[0] & 0x7fffffff) % 1000000).zfill(6)
token = call('POST', '/v1/identity/login', {'email': admin['email'], 'password': admin['password'], 'otp': otp}, expected=201)[0]['token']
step_file.write_text(str(step))
step_file.chmod(0o600)
try:
    me = call('GET', '/v1/identity/me')[0]
    assert me['platformAdmin'] is True
    state_file = args.directory / 'media-verification.json'
    state = json.loads(state_file.read_text()) if state_file.exists() else {}
    for name, mime in [('qualification.png', 'image/png'), ('qualification.mp4', 'video/mp4')]:
        content = (args.directory / name).read_bytes()
        if name not in state:
            asset = call('POST', '/v1/media/uploads', {
                'fileName': name, 'mime': mime, 'size': len(content),
                'sha256': hashlib.sha256(content).hexdigest(), 'purpose': 'training',
            }, expected=201)[0]
            state[name] = {'id': asset['id'], 'offset': 0}
            state_file.write_text(json.dumps(state))
            state_file.chmod(0o600)
        item = state[name]
        route = '/v1/media/uploads/' + item['id']
        status = call('GET', route)[0]
        if status['status'] not in {'processing', 'ready'}:
            # A replay of the same complete chunk must not create another file.
            for _ in range(2):
                call('PUT', route, content, headers={'Content-Type': 'application/octet-stream', 'Upload-Offset': '0'})
        for _ in range(120):
            status = call('GET', route)[0]
            assert status['status'] not in {'failed', 'expired'}, 'Media processing failed'
            if status['status'] == 'ready':
                break
            time.sleep(1)
        assert status['status'] == 'ready', 'Media processing timed out'
        route = '/v1/media/' + item['id']
        meta = call('GET', route + '/metadata')[0]
        data, headers = call('GET', route)
        assert len(data) == int(meta['size']) and hashlib.sha256(data).hexdigest() == meta['sha256']
        assert headers['X-Content-SHA256'] == meta['sha256']
        assert 'no-store' in headers.get('Cache-Control', '').lower()
        assert headers.get('CF-Cache-Status', '').upper() not in {'HIT', 'STALE', 'UPDATING'}
        partial, range_headers = call('GET', route, expected=206, headers={'Range': 'bytes=10-49', 'If-Range': headers['ETag']})
        assert partial == data[10:50] and range_headers['Content-Range'] == f'bytes 10-49/{len(data)}'
        item.update({'processedBytes': len(data), 'sha256': meta['sha256'], 'verified': True})
        state_file.write_text(json.dumps(state, indent=2) + '\n')
    print('PASS: health, access denial, MFA login, two unpublished processed media assets, repeated uploads, SHA-256 and protected HTTP ranges')
finally:
    call('POST', '/v1/identity/logout', expected=201)
call('GET', '/v1/identity/me', expected=401)
print('PASS: logout revokes the session; no stores, sales or invitations created')
