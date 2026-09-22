#!/usr/bin/env python3
"""Verify exported iOS distribution signatures on the authorized macOS host."""
import pathlib, plistlib, re, stat, subprocess, sys, tempfile, zipfile

def verify(ipa, expected_team):
    if not re.fullmatch('[A-Z0-9]{10}', expected_team): raise ValueError('An Apple team ID is required')
    with tempfile.TemporaryDirectory(prefix='biobalance-ipa-') as temporary:
        root=pathlib.Path(temporary)
        with zipfile.ZipFile(ipa) as archive:
            for item in archive.infolist():
                if not (root/item.filename).resolve().is_relative_to(root): raise ValueError('Invalid IPA path')
                if stat.S_ISLNK(item.external_attr >> 16):
                    target=pathlib.PurePosixPath(archive.read(item).decode('utf-8'))
                    if target.is_absolute() or '..' in target.parts: raise ValueError('Invalid IPA symbolic link')
        # Preserve the framework symlinks and executable permissions codesign verifies.
        subprocess.run(['ditto','-x','-k',str(ipa),str(root)],check=True,capture_output=True)
        apps=list((root/'Payload').glob('*.app'))
        if len(apps)!=1: raise ValueError('Expected one iOS app')
        app=apps[0]
        subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True,capture_output=True)
        details=subprocess.run(['codesign','-dv','--verbose=4',str(app)],check=True,capture_output=True,text=True).stderr
        if f'TeamIdentifier={expected_team}\n' not in details or 'Identifier=tn.biobalance.app\n' not in details:
            raise ValueError('Unexpected iOS signing identity')
        entitlements=plistlib.loads(subprocess.check_output(['codesign','-d','--entitlements',':-',str(app)],stderr=subprocess.DEVNULL))
        if entitlements.get('get-task-allow',False): raise ValueError('Distribution app permits debugging')
        if entitlements.get('application-identifier')!=f'{expected_team}.tn.biobalance.app': raise ValueError('Unexpected entitlement identity')
        print(f'Verified iOS distribution signature for {expected_team}.tn.biobalance.app')

if __name__=='__main__':
    try: verify(sys.argv[1],sys.argv[2])
    except (ValueError, OSError, IndexError, subprocess.CalledProcessError): sys.exit('iOS signature verification failed')
