import copy
import hashlib
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2] / 'scripts/catalog'))
from activate_sample_prices import product_fields, recoverable_product, validate_samples


class SamplePricesTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)
        (self.root / 'image.jpg').write_bytes(b'\xff\xd8reviewed-test-image')
        self.previous = {
            'reference': 'BB-EAN-8697711622410', 'barcode': '8697711622410',
            'name': 'Déodorant distinct', 'description': 'Référence fournie.',
            'active': False, 'priceMillimes': None,
        }
        self.sample = {
            'reference': self.previous['reference'], 'priceKind': 'sample',
            'priceMillimes': '29000', 'imageFile': 'image.jpg',
            'imageSha256': hashlib.sha256((self.root / 'image.jpg').read_bytes()).hexdigest(),
        }

    def validate(self, samples=None):
        return validate_samples({'products': [self.previous]}, {
            'schemaVersion': 1, 'products': samples or [self.sample],
        }, self.root)

    def test_price_is_exact_and_visible_in_both_catalog_fields(self):
        self.validate()
        fields = product_fields(self.previous, self.sample)
        self.assertTrue(fields['name'].endswith(' — prix démo'))
        self.assertIn('29,000 TND', fields['description'])
        self.assertIn('fictif', fields['description'])
        self.assertEqual(self.previous['barcode'], fields['barcode'])

    def test_cannot_replace_a_sourced_price(self):
        self.previous['priceMillimes'] = '29000'
        with self.assertRaises(ValueError):
            self.validate()

    def test_requires_explicit_sample_provenance(self):
        self.sample['priceKind'] = 'official'
        with self.assertRaises(ValueError):
            self.validate()

    def test_rejects_duplicate_and_unknown_references(self):
        with self.assertRaises(ValueError):
            self.validate([self.sample, self.sample])
        other = {**self.sample, 'reference': 'BB-WEB-999'}
        with self.assertRaises(ValueError):
            self.validate([other])

    def test_rejects_changed_image_and_outside_path(self):
        (self.root / 'image.jpg').write_bytes(b'changed')
        with self.assertRaises(ValueError):
            self.validate()
        self.sample['imageFile'] = '../image.jpg'
        with self.assertRaises(ValueError):
            self.validate()

    def test_business_edit_blocks_amendment(self):
        current = {**self.previous, 'id': 'stable-product', 'version': 2, 'imageId': None}
        desired = product_fields(self.previous, self.sample)
        with self.assertRaises(ValueError):
            recoverable_product(current, self.previous, desired, {'id': current['id'], 'version': 1})

    def test_lost_response_recovers_only_exact_product_and_identity(self):
        desired = product_fields(self.previous, self.sample)
        current = {**desired, 'id': 'stable-product', 'version': 2}
        self.assertTrue(recoverable_product(current, self.previous, desired, {'id': current['id'], 'version': 1}))
        with self.assertRaises(ValueError):
            recoverable_product(current, self.previous, desired, {'id': 'foreign-product', 'version': 1})
        edited = {**current, 'name': 'User changed this'}
        with self.assertRaises(ValueError):
            recoverable_product(edited, self.previous, desired, {'id': current['id'], 'version': 1})


if __name__ == '__main__':
    unittest.main()
