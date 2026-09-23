#!/usr/bin/env python3
"""Fail before compilation on test endpoints, embedded secrets."""
import ipaddress
import json
import re
import sys
from urllib.parse import urlsplit

FIELDS = {'API_BASE_URL'}

def validate(config, mode, platform):
    if mode not in {'compile-only', 'signed'} or platform not in {'android', 'ios'}:
        raise ValueError('Use compile-only|signed and android|ios')
    if not FIELDS <= set(config) or set(config) - FIELDS - {'AUTH_LINK_HOST', 'ANDROID_INSTALLATION'} or any(not isinstance(v, str) for v in config.values()):
        raise ValueError('Exactly the documented public mobile configuration fields are required')
    installation = config.get('ANDROID_INSTALLATION', '')
    if installation not in {'', 'admin', 'responsable', 'vendeur'}:
        raise ValueError('Unsupported Android installation')
    if platform != 'android' and installation:
        raise ValueError('Private Android installations cannot be used for iOS')
    host = config.get('AUTH_LINK_HOST', '')
    if host and (not re.fullmatch(r'[a-z0-9]+(?:[a-z0-9.-]*[a-z0-9])?',host) or '.' not in host or host.endswith(('.invalid','.test','.local'))):
        raise ValueError('AUTH_LINK_HOST must be an owned public DNS name')
    if config['API_BASE_URL'].strip() != config['API_BASE_URL']:
        raise ValueError('API_BASE_URL must not contain surrounding whitespace')
    url = urlsplit(config['API_BASE_URL'])
    if url.port is not None and not 1 <= url.port <= 65535:
        raise ValueError('Invalid API port')
    if url.scheme != 'https' or not url.hostname or url.username or url.password or url.query or url.fragment or url.path not in {'', '/'}:
        raise ValueError('API_BASE_URL must be an HTTPS origin without credentials, query or path')
    if mode == 'compile-only':
        if url.hostname != 'api.example.invalid' or host:
            raise ValueError('Compilation-only artifacts require the reserved invalid origin and no account-link host')
        return
    hostname = url.hostname.lower()
    if hostname.endswith('.'):
        raise ValueError('Use a canonical API hostname without a trailing dot')
    if any('REPLACE' in config[k] or not config[k] for k in FIELDS):
        raise ValueError('Supply the owned API origin')
    if hostname in {'localhost', 'example.com', 'example.org', 'example.net'} or hostname.endswith(('.invalid', '.test', '.example', '.local', '.localhost', '.example.com', '.example.org', '.example.net')) or '.' not in hostname or '_' in hostname:
        raise ValueError('A real owned API domain is required')
    try:
        ipaddress.ip_address(hostname)
    except ValueError:
        pass
    else:
        raise ValueError('Use the owned API DNS name')

if __name__ == '__main__':
    try:
        with open(sys.argv[1], encoding='utf-8') as source:
            validate(json.load(source), sys.argv[2], sys.argv[3])
    except (ValueError, KeyError, IndexError, OSError) as error:
        sys.exit(f'Invalid mobile build configuration: {error}')
