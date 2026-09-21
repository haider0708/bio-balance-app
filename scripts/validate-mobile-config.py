#!/usr/bin/env python3
"""Fail before compilation on test endpoints, missing push config or embedded secrets."""
import ipaddress
import json
import sys
from urllib.parse import urlsplit

FIELDS = {'API_BASE_URL', 'FIREBASE_API_KEY', 'FIREBASE_APP_ID', 'FIREBASE_SENDER_ID', 'FIREBASE_PROJECT_ID'}

def validate(config, mode, platform):
    if mode not in {'compile-only', 'signed'} or platform not in {'android', 'ios'}:
        raise ValueError('Use compile-only|signed and android|ios')
    if set(config) != FIELDS or any(not isinstance(v, str) for v in config.values()):
        raise ValueError('Exactly the documented public mobile configuration fields are required')
    url = urlsplit(config['API_BASE_URL'])
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in {'', '/'}:
        raise ValueError('API_BASE_URL must be an HTTPS origin without credentials, query or path')
    if mode == 'compile-only':
        if url.hostname != 'api.example.invalid' or any(config[k] for k in FIELDS - {'API_BASE_URL'}):
            raise ValueError('Compilation-only artifacts require the reserved invalid origin and no Firebase config')
        return
    hostname = url.hostname.lower()
    if any('REPLACE' in v or not v for v in config.values()):
        raise ValueError('Supply all platform Firebase values and the owned API origin')
    if hostname in {'localhost', 'example.com', 'example.org', 'example.net'} or hostname.endswith(('.invalid', '.test', '.example', '.local', '.localhost', '.example.com', '.example.org', '.example.net')) or '.' not in hostname or '_' in hostname:
        raise ValueError('A real owned API domain is required')
    try:
        ipaddress.ip_address(hostname)
    except ValueError:
        pass
    else:
        raise ValueError('Use the owned API DNS name')
    if f':{platform}:' not in config['FIREBASE_APP_ID'] or not config['FIREBASE_SENDER_ID'].isdigit():
        raise ValueError('Firebase app ID must match the target platform and sender ID must be numeric')

if __name__ == '__main__':
    try:
        with open(sys.argv[1], encoding='utf-8') as source:
            validate(json.load(source), sys.argv[2], sys.argv[3])
    except (ValueError, KeyError, IndexError, OSError) as error:
        sys.exit(f'Invalid mobile build configuration: {error}')
