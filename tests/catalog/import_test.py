import pathlib,sys,tempfile,unittest,json
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[2]/'scripts/catalog'))
from import_catalog import validate
from operator_client import save_json,Client
class ImportTest(unittest.TestCase):
 def product(self):return {'reference':'BB-WEB-37','barcode':'8697711600760','active':True,'priceMillimes':'74000','imageFile':'images/a.jpg'}
 def test_valid_code_and_exact_millimes(self):self.assertEqual('74000',validate({'schemaVersion':1,'products':[self.product()]})[0]['priceMillimes'])
 def test_rejects_bad_check_digit(self):
  p=self.product();p['barcode']='8697711600761'
  with self.assertRaises(ValueError):validate({'schemaVersion':1,'products':[p]})
 def test_rejects_duplicate_reference_and_barcode(self):
  with self.assertRaises(ValueError):validate({'schemaVersion':1,'products':[self.product(),self.product()]})
 def test_active_missing_price_is_not_zero(self):
  p=self.product();p['priceMillimes']=None
  with self.assertRaises(ValueError):validate({'schemaVersion':1,'products':[p]})
 def test_review_entry_preserves_barcode(self):
  p=self.product();p.update(active=False,priceMillimes=None,imageFile=None)
  self.assertEqual(p,validate({'schemaVersion':1,'products':[p]})[0])
 def test_checkpoint_is_private_and_atomic(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'state.json';save_json(p,{'id':'stable'});save_json(p,{'id':'stable','complete':True})
   self.assertEqual(0o600,p.stat().st_mode&0o777);self.assertEqual('stable',json.loads(p.read_text())['id']);self.assertFalse(p.with_suffix('.json.tmp').exists())
 def test_rejects_insecure_remote_origin_before_login(self):
  for origin in ['http://example.com','https://user:secret@example.com','https://example.com/path','https://example.com?token=x']:
   with self.assertRaises(ValueError):Client(origin,{},'.')
if __name__=='__main__':unittest.main()
