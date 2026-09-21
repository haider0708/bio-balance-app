import importlib.util
from pathlib import Path
import unittest
spec = importlib.util.spec_from_file_location('validator', Path(__file__).resolve().parents[2]/'scripts/validate-mobile-config.py')
module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class BuildConfigTest(unittest.TestCase):
    def setUp(self):
        self.config = {'API_BASE_URL':'https://api.biobalance.tn','FIREBASE_API_KEY':'public-client-key','FIREBASE_APP_ID':'1:123:android:abc','FIREBASE_SENDER_ID':'123','FIREBASE_PROJECT_ID':'synthetic-project'}
    def test_signed_platform_and_origin(self):
        module.validate(self.config,'signed','android')
        with self.assertRaises(ValueError): module.validate(self.config,'signed','ios')
    def test_reserved_origins_credentials_and_http_rejected(self):
        for origin in ['http://api.biobalance.tn','https://api.example.invalid','https://localhost','https://10.0.0.1','https://user:password@api.biobalance.tn','https://api.biobalance.tn/v1','https://api.example.com']:
            with self.subTest(origin=origin),self.assertRaises(ValueError): module.validate({**self.config,'API_BASE_URL':origin},'signed','android')
    def test_no_unknown_embedded_fields_or_partial_firebase(self):
        for value in [{**self.config,'TEST_PASSWORD':'private'},{**self.config,'FIREBASE_APP_ID':''}]:
            with self.assertRaises(ValueError): module.validate(value,'signed','android')
    def test_compilation_only_cannot_target_a_real_environment(self):
        with self.assertRaises(ValueError): module.validate(self.config,'compile-only','android')
        value={k:'' for k in module.FIELDS};value['API_BASE_URL']='https://api.example.invalid'
        module.validate(value,'compile-only','android')
if __name__ == '__main__': unittest.main()
