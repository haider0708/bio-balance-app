"""Shared source identity and independent artifact verification for releases."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def tracked_files(root):
    return sorted(filter(None, subprocess.check_output(
        ['git', 'ls-files', '-z'], cwd=root).decode().split('\0')))


def source_identity(root):
    source = hashlib.sha256()
    for name in tracked_files(root):
        path = root / name
        if path.is_file():
            source.update(name.encode() + b'\0' + bytes.fromhex(sha256(path)))
    return {
        'gitHead': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(),
        'workingTreeDirty': bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root)),
        'trackedSourceSha256': source.hexdigest(),
    }


def verify_signatures(root, build, manifest):
    if manifest['mode'] != 'signed':
        return
    if manifest['platform'] == 'android':
        apk, bundle = build / 'biobalance-signed.apk', build / 'biobalance-signed.aab'
        if not apk.is_file() or not bundle.is_file():
            raise ValueError('Signed Android packages require both the APK and AAB')
        policy = json.loads((root / 'config/signing/android-certificates.json').read_text())
        sdk = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
        if not sdk:
            raise ValueError('ANDROID_HOME is required for independent APK verification')
        candidates = list((Path(sdk) / 'build-tools').glob('*/apksigner'))
        if not candidates:
            raise ValueError('Install Android build-tools before packaging')
        signer = max(candidates, key=lambda p: tuple(int(n) for n in re.findall(r'\d+', p.parent.name)))
        subprocess.run([sys.executable, str(root / 'scripts/verify-android-signer.py'),
                        'apk', str(apk), str(signer), policy['appCertificateSha256']],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        subprocess.run(['java', str(root / 'scripts/VerifyAndroidBundle.java'),
                        str(bundle), policy['uploadCertificateSha256']],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    else:
        if sys.platform != 'darwin':
            raise ValueError('Signed iOS packages must be verified on macOS')
        signing = (root / 'apps/mobile/ios/Flutter/Signing.xcconfig').read_text()
        team = re.search(r'^DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10})\s*$', signing, re.M)
        ipas = list(build.glob('*.ipa'))
        if not team or len(ipas) != 1:
            raise ValueError('Configure the approved Apple team and provide exactly one IPA')
        subprocess.run([sys.executable, str(root / 'scripts/verify-ios-signature.py'),
                        str(ipas[0]), team[1]], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def verify_build(root, build, identity):
    manifest = json.loads((build / 'manifest.json').read_text())
    if (manifest.get('mode') not in {'signed', 'compile-only'}
            or manifest.get('platform') not in {'android', 'ios'}
            or manifest.get('entrypoint') != 'lib/main.dart'):
        raise ValueError('Unrecognized mobile build manifest')
    if identity['workingTreeDirty'] or any(manifest.get(k) != v for k, v in identity.items()):
        raise ValueError('Build must match the current clean source revision and digest; rebuild after committing')
    files = list(build.rglob('*'))
    checksums = manifest.get('sha256')
    if not isinstance(checksums, dict) or not checksums:
        raise ValueError('Missing build checksums')
    actual = {p.relative_to(build).as_posix() for p in files if p.is_file()}
    if actual != set(checksums) | {'manifest.json'} or any(p.is_symlink() for p in files):
        raise ValueError('Unexpected files or symlinks in the build directory')
    for name, digest in checksums.items():
        path = (build / name).resolve()
        if not path.is_relative_to(build) or sha256(path) != digest:
            raise ValueError('Build artifact checksum mismatch')
    verify_signatures(root, build, manifest)
    return manifest
