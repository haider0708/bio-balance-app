#!/usr/bin/env python3
"""Check actual certificate identity, validity and signature, not just ZIP entries."""
import hashlib, json, os, pathlib, re, subprocess, sys

def normalized(value):
    value = value.replace(':', '').lower()
    if not re.fullmatch('[a-f0-9]{64}', value): raise ValueError('Expected a SHA-256 certificate fingerprint')
    return value

def key(prefix, policy):
    expected = normalized(os.environ[prefix+'CERT_SHA256'])
    approved = json.loads(pathlib.Path(policy).read_text())
    field = 'uploadCertificateSha256' if prefix == 'BIOBALANCE_UPLOAD_' else 'appCertificateSha256'
    if expected != normalized(approved[field]): raise ValueError('Unexpected certificate policy')
    cert = subprocess.check_output(['keytool', '-exportcert', '-keystore', os.environ[prefix+'KEYSTORE'],
        '-alias', os.environ[prefix+'KEY_ALIAS'], '-storepass:env', prefix+'KEYSTORE_PASSWORD'], stderr=subprocess.PIPE)
    if hashlib.sha256(cert).hexdigest() != expected: raise ValueError('Keystore certificate does not match the approved identity')
    subprocess.run(['openssl','x509','-inform','DER','-checkend',str(365*86400),'-noout'], input=cert, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    details = subprocess.check_output(['openssl','x509','-inform','DER','-text','-noout'], input=cert).decode()
    if 'Android Debug' in details or not re.search(r'Public-Key: \((3072|4096|8192) bit\)', details) or 'sha256WithRSAEncryption' not in details:
        raise ValueError('Use a non-debug RSA 3072-bit or stronger SHA-256 certificate')
    print(f'Verified {prefix} signing certificate: {expected}')

def apk(path, signer, expected):
    output = subprocess.check_output([signer, 'verify', '--verbose', '--print-certs', path], text=True)
    digests = re.findall(r'^Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]+)$', output, re.M)
    if len(digests) != 1 or normalized(digests[0]) != normalized(expected):
        raise ValueError('APK signer does not match the approved app-signing identity')
    if 'Verified using v2 scheme (APK Signature Scheme v2): true' not in output:
        raise ValueError('APK v2 signing is required')
    print(output)

if __name__ == '__main__':
    try:
        if sys.argv[1] == 'key': key(sys.argv[2], sys.argv[3])
        elif sys.argv[1] == 'apk': apk(*sys.argv[2:])
        else: raise ValueError('Unknown verification mode')
    except (ValueError, KeyError, IndexError, subprocess.CalledProcessError):
        sys.exit('Signing verification failed. Check the expected certificate and artifact; private credentials are not logged.')
