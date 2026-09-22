#!/usr/bin/env python3
"""Sign only an inert compile-only build for signature/install verification."""
import hashlib, json, os, pathlib, shutil, subprocess, sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
source=pathlib.Path(sys.argv[1]).resolve();directory=pathlib.Path(sys.argv[2]).resolve();sdk=pathlib.Path(sys.argv[3]).resolve()
manifest=json.loads((source/'manifest.json').read_text())
if manifest['mode']!='compile-only' or json.loads((source/'public-mobile-config.json').read_text())['API_BASE_URL']!='https://api.example.invalid':
    raise SystemExit('Only an inert compile-only build is allowed')
identity=json.loads((directory/'identity.json').read_text())
approved=json.loads((ROOT/'config/signing/android-certificates.json').read_text())
out=ROOT/'.artifacts/evidence/security-hardening/android'/source.name;out.mkdir(parents=True,exist_ok=True)
signer=sorted(sdk.glob('build-tools/*/apksigner'))[-1]
for name,field in [('app','appCertificateSha256'),('upload','uploadCertificateSha256')]:
    if identity['keys'][name]['sha256']!=approved[field]:raise SystemExit('Unexpected signing identity')

def environment(name):
    key=identity['keys'][name];password=(directory/key['passwordFile']).read_text().strip()
    return key,{**os.environ,'TEST_SIGN_PASSWORD':password}
def run(args,env=None):
    return subprocess.run([str(x) for x in args],env=env,check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
for name in ['app','upload']:
    key,env=environment(name)
    run([signer,'sign','--ks',directory/key['keystore'],'--ks-key-alias',key['alias'],
         '--ks-pass','env:TEST_SIGN_PASSWORD','--key-pass','env:TEST_SIGN_PASSWORD',
         '--out',out/f'{name}-inert.apk',source/'biobalance-compile-only.apk'],env)
    run(['python3',ROOT/'scripts/verify-android-signer.py','apk',out/f'{name}-inert.apk',signer,key['sha256']])
key,env=environment('upload');bundle=out/'upload-inert.aab';shutil.copy2(source/'biobalance-compile-only.aab',bundle)
run(['jarsigner','-keystore',directory/key['keystore'],'-storepass:env','TEST_SIGN_PASSWORD','-keypass:env','TEST_SIGN_PASSWORD',
     '-sigalg','SHA256withRSA','-digestalg','SHA-256',bundle,key['alias']],env)
run(['java',ROOT/'scripts/VerifyAndroidBundle.java',bundle,key['sha256']])
wrong=subprocess.run(['python3',str(ROOT/'scripts/verify-android-signer.py'),'apk',str(out/'upload-inert.apk'),str(signer),approved['appCertificateSha256']],capture_output=True)
if wrong.returncode==0:raise SystemExit('Wrong APK signer was accepted')
# Damage an actual signed APK byte; the cryptographic verifier must reject it.
tampered=out/'tampered.apk';data=bytearray((out/'app-inert.apk').read_bytes());data[len(data)//2]^=1;tampered.write_bytes(data)
if subprocess.run([str(signer),'verify',str(tampered)],capture_output=True).returncode==0:raise SystemExit('Tampered APK accepted')
tampered.unlink()
report={'productionReady':False,'apiOrigin':'https://api.example.invalid','checks':['APK app signature','AAB upload signature and every entry','wrong APK signer rejected','modified APK rejected'],
        'sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.suffix in {'.apk','.aab'}},'certificates':approved}
(out/'signature-evidence.json').write_text(json.dumps(report,indent=2)+'\n')
print('PASS: inert APK/AAB signature verification, wrong signer and tampered APK rejection. These are not pilot builds.')
