#!/usr/bin/env python3
"""Load private signing material without putting passwords in CLI arguments/logs."""
import json, os, pathlib, stat, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[1]

def private_file(directory, name):
    file = directory / name
    if file.is_symlink() or not file.resolve().is_relative_to(directory) or not file.is_file():
        raise ValueError('Invalid signing file path')
    if stat.S_IMODE(file.stat().st_mode) & 0o077:
        raise ValueError('Signing material must only be readable by its owner')
    return file

def build(config, identity_directory):
    directory = pathlib.Path(identity_directory).expanduser().resolve()
    if directory.is_relative_to(root) or stat.S_IMODE(directory.stat().st_mode) & 0o077:
        raise ValueError('Use a private signing directory outside the repository')
    identity = json.loads(private_file(directory, 'identity.json').read_text())
    if identity['schema'] != 1 or identity['applicationId'] != 'tn.biobalance.app':
        raise ValueError('Wrong signing identity')
    approved = json.loads((root/'config/signing/android-certificates.json').read_text())
    for name, field in [('app','appCertificateSha256'), ('upload','uploadCertificateSha256')]:
        if identity['keys'][name]['sha256'] != approved[field]:
            raise ValueError('Signing identity differs from the reviewed certificate fingerprints')
    env = dict(os.environ)
    for name, prefix in [('app', 'BIOBALANCE_'), ('upload', 'BIOBALANCE_UPLOAD_')]:
        key = identity['keys'][name]
        env[prefix+'KEYSTORE'] = str(private_file(directory, key['keystore']))
        password = private_file(directory, key['passwordFile']).read_text().strip()
        env.update({prefix+'KEYSTORE_PASSWORD': password, prefix+'KEY_PASSWORD': password,
                    prefix+'KEY_ALIAS': key['alias'], prefix+'CERT_SHA256': key['sha256']})
    subprocess.run(['bash', str(root/'scripts/build-mobile-release.sh'), 'signed', 'android', str(pathlib.Path(config).resolve())],
                   env=env, cwd=root, check=True)

if __name__ == '__main__':
    try: build(sys.argv[1], sys.argv[2])
    except (ValueError, OSError, KeyError, IndexError, subprocess.CalledProcessError) as error:
        sys.exit(f'Signed build stopped ({type(error).__name__}); inspect the preceding build result. No signing secrets are logged.')
