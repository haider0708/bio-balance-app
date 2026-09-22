#!/usr/bin/env python3
"""Exercise signed updates only on the dedicated synthetic security emulator."""
from pathlib import Path
import json, subprocess, sys, time
adb, serial, directory = sys.argv[1:]
out=Path(directory).resolve()
def run(*args,check=True):
    return subprocess.run([adb,'-s',serial,*args],capture_output=True,text=True,check=check)
if not serial.startswith('emulator-') or run('emu','avd','name').stdout.splitlines()[0]!='BioBalance_Security_API36':
    raise SystemExit('Use the isolated BioBalance_Security_API36 emulator only')
for attempt in range(60):
    if run('shell','getprop','sys.boot_completed',check=False).stdout.strip()=='1':break
    time.sleep(1)
else:raise SystemExit('Android startup did not finish within the test window')
run('install','-r',str(out/'app-inert.apk'))
launch=run('shell','am','start','-W','-n','tn.biobalance.app/.MainActivity')
(out/'launch.txt').write_text(launch.stdout)
time.sleep(2)
windows=run('shell','dumpsys','window','windows').stdout
if not any('tn.biobalance.app/tn.biobalance.app.MainActivity' in block and 'SECURE' in block for block in windows.split('Window #')):
    raise SystemExit('Secure window flag missing')
wrong=run('install','-r',str(out/'upload-inert.apk'),check=False)
if not wrong.returncode or 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' not in wrong.stdout+wrong.stderr:
    raise SystemExit('Wrong-key update was not refused')
run('install','-r',str(out/'app-inert.apk'))
report={'device':'BioBalance_Security_API36','androidApi':36,'productionReady':False,
        'artifactSha256':json.loads((out/'signature-evidence.json').read_text())['sha256']['app-inert.apk'],
        'passed':['signed release install/launch','SECURE window','wrong-key update rejected','same-key update accepted']}
(out/'installation-evidence.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: signed release installation, secure window and signature-enforced updates on the isolated emulator.')
