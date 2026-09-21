#!/usr/bin/env python3
import datetime, hashlib, json, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parent.parent
output = pathlib.Path(sys.argv[1]).resolve()
files = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode().split('\0')
source = hashlib.sha256()
for name in sorted(filter(None, files)):
    path = root / name
    if path.is_file():
        source.update(name.encode() + b'\0' + hashlib.sha256(path.read_bytes()).digest())
artifacts = {p.relative_to(output).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(output.rglob('*')) if p.is_file() and p.name != 'manifest.json'}
manifest = {'createdUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'gitHead': subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(), 'workingTreeDirty': bool(subprocess.check_output(['git','status','--porcelain'],cwd=root)), 'trackedSourceSha256': source.hexdigest(), 'mode':sys.argv[2], 'platform':sys.argv[3], 'entrypoint':'lib/main.dart', 'productionAccepted':False, 'sha256':artifacts}
(output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
