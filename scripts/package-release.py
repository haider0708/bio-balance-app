#!/usr/bin/env python3
"""Package a clean reviewed checkout and an explicitly selected mobile build."""
import hashlib,json,pathlib,shutil,subprocess,sys,tarfile
root=pathlib.Path(__file__).resolve().parent.parent
if subprocess.check_output(['git','status','--porcelain'],cwd=root):
    sys.exit('Commit the completed step before packaging; a clean tracked checkout is required')
build=pathlib.Path(sys.argv[1]).resolve()
if not build.is_relative_to(root/'.artifacts/releases/builds'):
    sys.exit('Choose a build produced under .artifacts/releases/builds')
manifest=json.loads((build/'manifest.json').read_text())
if manifest.get('mode') not in {'signed','compile-only'} or manifest.get('platform') not in {'android','ios'} or manifest.get('entrypoint') != 'lib/main.dart':
    sys.exit('Unrecognized mobile build manifest')
actual={p.relative_to(build).as_posix() for p in build.rglob('*') if p.is_file()}
if actual != set(manifest['sha256']) | {'manifest.json'} or any(p.is_symlink() for p in build.rglob('*')):
    sys.exit('Unexpected files or symlinks in the build directory; regenerate and inspect the manifest')
for name,digest in manifest['sha256'].items():
    file=(build/name).resolve()
    if not file.is_relative_to(build) or hashlib.sha256(file.read_bytes()).hexdigest()!=digest:
        sys.exit('Build artifact checksum mismatch')
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
output=root/'.artifacts/releases'/f'biobalance-{head[:8]}-{manifest["platform"]}-{manifest["mode"]}'
output.mkdir(exist_ok=False)
allowed=('docs/','contracts/openapi/','apps/api/prisma/migrations/','infrastructure/production/','scripts/','config/mobile/','config/signing/','tests/release/','tests/performance/evidence/')
singles={'README.md','package.json','package-lock.json','.nvmrc','.fvmrc','apps/mobile/pubspec.yaml','apps/mobile/pubspec.lock','apps/api/prisma/schema.prisma','tests/deployment/evidence.json'}
files=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
for name in filter(None,files):
    if name in singles or name.startswith(allowed):
        target=output/'project'/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/name,target)
subprocess.run(['git','archive','--format=tar.gz',f'--output={output/"source.tar.gz"}',head],cwd=root,check=True)
shutil.copytree(build,output/'mobile')
(output/'RELEASE-STATUS.txt').write_text(f'BioBalance source {head}\nBuild mode: {manifest["mode"]}\nNot accepted for production. See project/docs/release-gates.md.\n')
checks={p.relative_to(output).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.rglob('*')) if p.is_file()}
(output/'checksums.json').write_text(json.dumps(checks,indent=2)+'\n')
archive=output.with_suffix('.tar.gz')
with tarfile.open(archive,'w:gz') as tar:tar.add(output,arcname=output.name)
print(f'Package: {archive}\nSHA-256: {hashlib.sha256(archive.read_bytes()).hexdigest()}')
