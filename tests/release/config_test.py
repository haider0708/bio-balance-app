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
if __name__ == '__main__': unittest.main()
