#!/usr/bin/env python3
"""Check ZIP and ELF alignment for modern Android 16 KiB page devices."""
import pathlib
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
count = 0
with tempfile.TemporaryDirectory(prefix='biobalance-elf-') as directory, zipfile.ZipFile(apk) as bundle:
    for name in bundle.namelist():
        if name.startswith(('lib/arm64-v8a/', 'lib/x86_64/')) and name.endswith('.so'):
            path = pathlib.Path(directory)/pathlib.Path(name).name
            path.write_bytes(bundle.read(name))
            headers = subprocess.check_output([str(readers[-1]), '-lW', str(path)], text=True)
            alignments = [int(line.split()[-1], 16) for line in headers.splitlines() if line.strip().startswith('LOAD ')]
            if not alignments or min(alignments) < 16384:
                sys.exit(f'Native load alignment is below 16 KiB: {name}')
            count += 1
            print(f'PASS: {name}: load alignment >= 16 KiB')
if not count:
    sys.exit('Expected native 64-bit libraries are missing')
print('PASS: APK ZIP alignment and all native 64-bit load segments')
