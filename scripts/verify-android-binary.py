#!/usr/bin/env python3
"""Check ZIP and ELF alignment for modern Android 16 KiB page devices."""
import pathlib
import re
import subprocess
import sys
import tempfile
import zipfile

apk, sdk = pathlib.Path(sys.argv[1]).resolve(), pathlib.Path(sys.argv[2]).resolve()
readers = sorted(sdk.glob('ndk/*/toolchains/llvm/prebuilt/*/bin/llvm-readelf'))
if not readers:
    sys.exit('Install the pinned Android NDK before verifying native alignment')
aligners = sorted(sdk.glob('build-tools/*/zipalign'))
if not aligners:
    sys.exit('Android build-tools are required for ZIP alignment verification')
subprocess.run([str(aligners[-1]), '-c', '-P', '16', '4', str(apk)], check=True)
aapt = sorted(sdk.glob('build-tools/*/aapt2'))[-1]
manifest = subprocess.check_output([str(aapt), 'dump', 'xmltree', str(apk), '--file', 'AndroidManifest.xml'], text=True)
if 'A: package="tn.biobalance.app"' not in manifest:
    sys.exit('Unexpected Android application ID')
for attribute in ['allowBackup', 'usesCleartextTraffic']:
    if not re.search(r':'+attribute+r'\([^)]*\)=false', manifest):
        sys.exit(f'Unsafe release manifest: {attribute}')
if re.search(r':debuggable\([^)]*\)=true', manifest):
    sys.exit('A release artifact must not permit debugging')
print('PASS: release application ID, backups, cleartext and debugging policy')
count = 0
with tempfile.TemporaryDirectory(prefix='biobalance-elf-') as directory, zipfile.ZipFile(apk) as bundle:
    for name in bundle.namelist():
        if name.startswith('lib/') and name.endswith('.so'):
            path = pathlib.Path(directory)/pathlib.Path(name).name
            path.write_bytes(bundle.read(name))
            sections = subprocess.check_output([str(readers[-1]), '-SW', str(path)], text=True)
            if '.debug_info' in sections or '.debug_line' in sections:
                sys.exit(f'Unstripped debug information in distributed library: {name}')
            headers = subprocess.check_output([str(readers[-1]), '-lW', str(path)], text=True)
            alignments = [int(line.split()[-1], 16) for line in headers.splitlines() if line.strip().startswith('LOAD ')]
            if not name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')):
                print(f'PASS: {name}: no embedded DWARF debug information')
                continue
            if not alignments or min(alignments) < 16384:
                sys.exit(f'Native load alignment is below 16 KiB: {name}')
            count += 1
            print(f'PASS: {name}: load alignment >= 16 KiB')
if not count:
    sys.exit('Expected native 64-bit libraries are missing')
print('PASS: APK ZIP alignment and all native 64-bit load segments')
