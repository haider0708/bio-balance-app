import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location("capacity",pathlib.Path(__file__).resolve().parents[2]/"scripts/backup_storage.py")
module=importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class BackupCapacityTest(unittest.TestCase):
    def test_budget_refuses_without_deleting_retained_backup(self):
        with tempfile.TemporaryDirectory() as root:
            backup=pathlib.Path(root)/"database.dump"
            backup.write_bytes(b"retained")
            with self.assertRaises(ValueError): module.check(root,10,maximum=15,reserve=1)
            self.assertEqual(backup.read_bytes(),b"retained")
    def test_disk_reserve_is_protected(self):
        with tempfile.TemporaryDirectory() as root:
            with patch.object(module.shutil,"disk_usage",return_value=type("Usage",(),{"free":12})()):
                with self.assertRaises(ValueError): module.check(root,10,maximum=100,reserve=5)
                module.check(root,5,maximum=100,reserve=5)
