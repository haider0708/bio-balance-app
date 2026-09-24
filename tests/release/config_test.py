import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('validator', Path(__file__).resolve().parents[2]/'scripts/validate-mobile-config.py')
module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class BuildConfigTest(unittest.TestCase):
    def setUp(self):
        self.config = {'API_BASE_URL':'https://api.biobalance.tn'}
    def test_signed_platform_and_origin(self):
        module.validate(self.config,'signed','android')
        module.validate(self.config,'signed','ios')
    def test_reserved_origins_credentials_and_http_rejected(self):
        for origin in ['http://api.biobalance.tn','https://api.example.invalid','https://localhost','https://10.0.0.1','https://user:password@api.biobalance.tn','https://api.biobalance.tn/v1','https://api.example.com','https://api.biobalance.tn:invalid','https://api.biobalance.tn:0','https://api.biobalance.tn.',' https://api.biobalance.tn']:
            with self.subTest(origin=origin),self.assertRaises(ValueError): module.validate({**self.config,'API_BASE_URL':origin},'signed','android')
    def test_no_secrets_or_obsolete_firebase_fields(self):
        for value in [{**self.config,'TEST_PASSWORD':'private'},{**self.config,'FIREBASE_APP_ID':'obsolete'}]:
            with self.assertRaises(ValueError): module.validate(value,'signed','android')
    def test_compilation_only_cannot_target_a_real_environment(self):
        with self.assertRaises(ValueError): module.validate(self.config,'compile-only','android')
        value={k:'' for k in module.FIELDS};value['API_BASE_URL']='https://api.example.invalid'
        module.validate(value,'compile-only','android')
    def test_private_installations_are_explicit_and_android_only(self):
        for installation in ['admin','responsable','vendeur','vendeur2']:
            value = {**self.config,'ANDROID_INSTALLATION':installation}
            module.validate(value,'signed','android')
            with self.assertRaises(ValueError): module.validate(value,'signed','ios')
        with self.assertRaises(ValueError):
            module.validate({**self.config,'ANDROID_INSTALLATION':'arbitrary.package'},'signed','android')
if __name__ == '__main__': unittest.main()

class BuildToolchainPolicyTest(unittest.TestCase):
    def test_installs_disable_unapproved_hooks_and_gradle_is_checksum_pinned(self):
        root = Path(__file__).resolve().parents[2]
        self.assertIn('ignore-scripts=true', (root / '.npmrc').read_text())
        self.assertIn('strict-allow-scripts=true', (root / '.npmrc').read_text())
        script = (root / 'scripts/install-dependencies.sh').read_text()
        self.assertIn('npm ci --ignore-scripts', script)
        self.assertIn('npm rebuild --ignore-scripts=false argon2 prisma @prisma/engines esbuild', script)
        import re
        properties = (root / 'apps/mobile/android/gradle/wrapper/gradle-wrapper.properties').read_text()
        self.assertRegex(properties, r'distributionSha256Sum=[a-f0-9]{64}')
