import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
from release_integrity import source_identity

class ReleasePackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='biobalance-package-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root/'scripts').mkdir()
        shutil.copy2(Path(__file__).resolve().parents[2]/'scripts/package-release.py', self.root/'scripts/package-release.py')
        shutil.copy2(Path(__file__).resolve().parents[2]/'scripts/release_integrity.py', self.root/'scripts/release_integrity.py')
        (self.root/'docs').mkdir()
        (self.root/'docs/release-gates.md').write_text('Physical devices and signing pending.\n')
        (self.root/'.gitignore').write_text('.artifacts/\n.env\n__pycache__/\n')
        (self.root/'.env').write_text('PRIVATE_VALUE=must-never-be-packaged\n')
        (self.root/'tests/audit').mkdir(parents=True)
        (self.root/'tests/audit/final-evidence-2026-09-22.json').write_text('{"productionAccepted":false}\n')
        (self.root/'.artifacts/evidence').mkdir(parents=True)
        (self.root/'.artifacts/evidence/private.log').write_text('private fixture token\n')
        for args in [['init','-q'],['add','.'],['-c','user.name=Test','-c','user.email=test@example.test','commit','-qm','Fixture']]:
            subprocess.run(['git',*args],cwd=self.root,check=True,stdout=subprocess.DEVNULL)
        self.build=self.root/'.artifacts/releases/builds/fixture';self.build.mkdir(parents=True)
        (self.build/'example.apk').write_bytes(b'compilation-test-bytes')
        self.manifest={'mode':'compile-only','platform':'android','entrypoint':'lib/main.dart','sha256':{'example.apk':hashlib.sha256(b'compilation-test-bytes').hexdigest()}}
        self.manifest.update(source_identity(self.root))
        self.save()
    def save(self): (self.build/'manifest.json').write_text(json.dumps(self.manifest))
    def run_package(self):
        return subprocess.run(['python3','scripts/package-release.py',str(self.build)],cwd=self.root,text=True,capture_output=True)
    def test_clean_package_excludes_private_working_files(self):
        result=self.run_package();self.assertEqual(result.returncode,0,result.stderr)
        archive=next((self.root/'.artifacts/releases').glob('*.tar.gz'))
        with tarfile.open(archive) as tar:
            names=tar.getnames()
            self.assertFalse(any('/.env' in p or '/.artifacts/' in p for p in names))
            self.assertTrue(any(p.endswith('/docs/release-gates.md') for p in names))
            self.assertTrue(any(p.endswith('/project/tests/audit/final-evidence-2026-09-22.json') for p in names))
            self.assertFalse(any(p.endswith('/private.log') for p in names))
            source=next(m for m in tar.getmembers() if m.name.endswith('/source.tar.gz'))
            with tarfile.open(fileobj=tar.extractfile(source),mode='r:gz') as src:
                self.assertNotIn('.env',src.getnames())
    def test_unlisted_file_or_tampered_build_is_rejected(self):
        (self.build/'secret.key').write_text('not allowed')
        self.assertNotEqual(self.run_package().returncode,0)
        (self.build/'secret.key').unlink()
        (self.build/'example.apk').write_bytes(b'modified')
        self.assertNotEqual(self.run_package().returncode,0)
    def test_foreign_entrypoint_and_path_are_rejected(self):
        self.manifest['entrypoint']='integration_test/role_journeys_test.dart';self.save()
        self.assertNotEqual(self.run_package().returncode,0)
        self.manifest['entrypoint']='lib/main.dart';self.manifest['mode']='../../outside';self.save()
        self.assertNotEqual(self.run_package().returncode,0)
    def test_stale_source_or_dirty_build_metadata_is_rejected(self):
        original = self.manifest.copy()
        for field, wrong in [('gitHead', '0' * 40), ('trackedSourceSha256', '0' * 64), ('workingTreeDirty', True)]:
            with self.subTest(field=field):
                self.manifest = {**original, field: wrong}
                self.save()
                self.assertNotEqual(self.run_package().returncode, 0)
        self.assertFalse(list((self.root/'.artifacts/releases').glob('*.tar.gz')))

    def test_forged_signed_label_cannot_authenticate_arbitrary_bytes(self):
        self.manifest['mode'] = 'signed'
        self.save()
        self.assertNotEqual(self.run_package().returncode, 0)
        self.assertFalse(list((self.root/'.artifacts/releases').glob('*.tar.gz')))

if __name__ == '__main__': unittest.main()
