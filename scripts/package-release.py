#!/usr/bin/env python3
"""Package a clean source revision and independently verified mobile artifacts."""
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile
from release_integrity import sha256, source_identity, tracked_files, verify_build

ALLOWED = ('docs/', 'contracts/openapi/', 'apps/api/prisma/migrations/',
           'infrastructure/production/', 'scripts/', 'config/mobile/', 'config/signing/',
           'tests/release/', 'tests/performance/evidence/')
SINGLES = {'README.md', 'package.json', 'package-lock.json', '.nvmrc', '.fvmrc',
           'apps/mobile/pubspec.yaml', 'apps/mobile/pubspec.lock',
           'apps/api/prisma/schema.prisma', 'tests/deployment/evidence.json'}


def package(root, selected):
    identity = source_identity(root)
    if identity['workingTreeDirty']:
        raise ValueError('Commit the completed step before packaging; a clean checkout is required')
    build = Path(selected).resolve()
    releases = root / '.artifacts/releases'
    if not build.is_relative_to(releases / 'builds'):
        raise ValueError('Choose a build produced under .artifacts/releases/builds')
    manifest = verify_build(root, build, identity)
    name = f'biobalance-{identity["gitHead"][:8]}-{manifest["platform"]}-{manifest["mode"]}'
    archive = releases / f'{name}.tar.gz'
    if archive.exists():
        raise ValueError('This release package already exists')
    # Failed verification never leaves an apparently complete release directory.
    with tempfile.TemporaryDirectory(prefix='package-', dir=releases) as temporary:
        output = Path(temporary) / name
        output.mkdir()
        for path in tracked_files(root):
            item = PurePosixPath(path)
            evidence = path.startswith('tests/') and item.suffix == '.json' and 'evidence' in item.stem
            if path in SINGLES or path.startswith(ALLOWED) or evidence:
                target = output / 'project' / path
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(root / path, target)
        subprocess.run(['git', 'archive', '--format=tar.gz',
                        f'--output={output / "source.tar.gz"}', identity['gitHead']], cwd=root, check=True)
        shutil.copytree(build, output / 'mobile', symlinks=True)
        # Verify copied bytes too, so changing the input while copying fails closed.
        verify_build(root, output / 'mobile', identity)
        (output / 'RELEASE-STATUS.txt').write_text(
            f'BioBalance source {identity["gitHead"]}\nBuild mode: {manifest["mode"]}\n'
            'Compile-only artifacts are not distributable.\n'
            'Not accepted for production. See project/docs/release-gates.md.\n')
        checks = {p.relative_to(output).as_posix(): sha256(p)
                  for p in sorted(output.rglob('*')) if p.is_file()}
        (output / 'checksums.json').write_text(json.dumps(checks, indent=2) + '\n')
        staged = Path(temporary) / 'package.tar.gz'
        with tarfile.open(staged, 'w:gz') as tar:
            tar.add(output, arcname=name)
        staged.rename(archive)
    print(f'Package: {archive}\nSHA-256: {sha256(archive)}')


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('Usage: package-release.py BUILD_DIRECTORY')
        package(Path(__file__).resolve().parent.parent, sys.argv[1])
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        # Subprocess stderr may contain operator-local details; do not relay it.
        sys.exit(str(error) if isinstance(error, ValueError) else 'Release verification failed; check the source, toolchain and artifact identity')
