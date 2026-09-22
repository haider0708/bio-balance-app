#!/usr/bin/env python3
"""Create and verify an encrypted backup of existing Android signing identities.

Neither key is regenerated. No plaintext archive is written. The recovery key
must be moved to a separate secure location by the owner for independent backup.
"""
import argparse
import hashlib
import io
import json
import pathlib
import secrets
import subprocess
import tarfile
import tempfile


def run(source, destination):
    repository = pathlib.Path(__file__).resolve().parents[1]
    source = source.expanduser().resolve()
    destination = destination.expanduser().resolve()
    if source.is_relative_to(repository) or destination.is_relative_to(repository):
        raise ValueError('Signing material and backups must remain outside Git')
    if destination == source or destination.is_relative_to(source):
        raise ValueError('Use a separate backup directory')
    names = ['identity.json', 'app.jks', 'upload.jks', 'app.password',
             'upload.password', 'app.der', 'upload.der']
    contents = {}
    for name in names:
        path = source / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size > 1024 * 1024:
            raise ValueError('Unexpected signing input')
        contents[name] = path.read_bytes()
    identity = json.loads(contents['identity.json'])
    if identity['applicationId'] != 'tn.biobalance.app':
        raise ValueError('Unexpected application identity')
    for kind in ['app', 'upload']:
        item = identity['keys'][kind]
        if item['keystore'] != kind + '.jks' or item['passwordFile'] != kind + '.password':
            raise ValueError('Unexpected identity path')
        certificate = subprocess.check_output([
            'keytool', '-exportcert', '-keystore', str(source / item['keystore']),
            '-alias', item['alias'], '-storepass:file', str(source / item['passwordFile']),
        ], stderr=subprocess.PIPE)
        if certificate != contents[kind + '.der'] or hashlib.sha256(certificate).hexdigest() != item['sha256']:
            raise ValueError('Signing certificate mismatch')
    destination.mkdir(mode=0o700, parents=True, exist_ok=False)
    recovery = destination / 'recovery-key.txt'
    recovery.write_text(secrets.token_urlsafe(48) + '\n')
    recovery.chmod(0o600)
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode='w') as archive:
        for name, data in contents.items():
            member = tarfile.TarInfo(name)
            member.size, member.mode = len(data), 0o600
            archive.addfile(member, io.BytesIO(data))
    encrypted = destination / 'biobalance-android-signing.tar.gpg'
    with tempfile.TemporaryDirectory(prefix='biobalance-gpg-') as home:
        common = ['gpg', '--homedir', home, '--batch', '--pinentry-mode', 'loopback',
                  '--no-symkey-cache', '--passphrase-file', str(recovery)]
        subprocess.run(common + ['--cipher-algo', 'AES256', '--symmetric',
                                 '--output', str(encrypted)],
                       input=buffer.getvalue(), check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        encrypted.chmod(0o600)
        restored = subprocess.check_output(common + ['--decrypt', str(encrypted)], stderr=subprocess.PIPE)
    if restored != buffer.getvalue():
        raise ValueError('Encrypted backup restoration mismatch')
    with tarfile.open(fileobj=io.BytesIO(restored)) as archive:
        if sorted(archive.getnames()) != sorted(names):
            raise ValueError('Restored backup inventory mismatch')
        for name, data in contents.items():
            if archive.extractfile(name).read() != data:
                raise ValueError('Restored signing file differs')
    report = {'applicationId': identity['applicationId'], 'verifiedFiles': len(names),
              'encryption': 'OpenPGP AES-256 with random 384-bit recovery secret',
              'archiveSha256': hashlib.sha256(encrypted.read_bytes()).hexdigest(),
              'restoreVerified': True, 'independentCopy': 'pending owner transfer'}
    (destination / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    (destination / 'README.txt').write_text(
        'Copier le fichier .gpg sur un support externe sécurisé. Conserver recovery-key.txt '
        'dans un gestionnaire de mots de passe ou un autre emplacement indépendant. '
        'Ne jamais les joindre à une release GitHub.\n'
        'Restauration : gpg --output signing.tar --decrypt biobalance-android-signing.tar.gpg\n'
        'Entrer la clé de récupération quand GPG la demande. Extraire dans un dossier privé '
        'vide (mode 700), vérifier identity.json, puis supprimer l’archive non chiffrée.\n'
        'La présence de ces deux fichiers sur le même ordinateur ne constitue pas une copie indépendante.\n'
    )
    print(json.dumps(report))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=pathlib.Path, required=True)
    parser.add_argument('--destination', type=pathlib.Path, required=True)
    args = parser.parse_args()
    try:
        run(args.source, args.destination)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit('Signing backup failed: ' + type(error).__name__ + '. Existing keys were not modified.')
