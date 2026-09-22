#!/usr/bin/env python3
"""Create a new local signing identity once; never replace an existing directory."""
import hashlib, json, os, pathlib, secrets, subprocess, sys

def provision(directory):
    root = pathlib.Path(__file__).resolve().parents[1]
    target = pathlib.Path(directory).expanduser().resolve()
    if target.is_relative_to(root):
        raise ValueError('Signing material must be outside the repository')
    target.mkdir(mode=0o700, parents=True, exist_ok=False)
    manifest = {'schema': 1, 'applicationId': 'tn.biobalance.app', 'keys': {}}
    for name in ['app', 'upload']:
        password = secrets.token_urlsafe(48)
        secret = target / f'{name}.password'
        secret.write_text(password); secret.chmod(0o600)
        keystore = target / f'{name}.jks'
        env = {**os.environ, 'BIOBALANCE_NEW_PASSWORD': password}
        subprocess.run(['keytool', '-genkeypair', '-noprompt', '-storetype', 'JKS',
            '-keystore', str(keystore), '-alias', f'biobalance-{name}',
            '-storepass:env', 'BIOBALANCE_NEW_PASSWORD', '-keypass:env', 'BIOBALANCE_NEW_PASSWORD',
            '-keyalg', 'RSA', '-keysize', '4096', '-sigalg', 'SHA256withRSA',
            '-validity', '10000', '-dname', f'CN=BioBalance {name}, OU=Mobile, O=BioBalance, C=TN'],
            env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        keystore.chmod(0o600)
        cert = subprocess.check_output(['keytool', '-exportcert', '-keystore', str(keystore),
            '-alias', f'biobalance-{name}', '-storepass:env', 'BIOBALANCE_NEW_PASSWORD'], env=env, stderr=subprocess.PIPE)
        (target / f'{name}.der').write_bytes(cert)
        manifest['keys'][name] = {'keystore': keystore.name, 'passwordFile': secret.name,
            'alias': f'biobalance-{name}', 'sha256': hashlib.sha256(cert).hexdigest()}
    (target / 'identity.json').write_text(json.dumps(manifest, indent=2)+'\n')
    (target / 'identity.json').chmod(0o600)
    print(f'Signing identity created in {target}. Back up this directory securely before distribution.')

if __name__ == '__main__':
    try: provision(sys.argv[1])
    except (ValueError, OSError, IndexError, subprocess.CalledProcessError) as error:
        sys.exit(f'Signing setup failed ({type(error).__name__}); existing material has not been overwritten. Inspect the target directory before retrying.')
