import datetime as dt
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = pathlib.Path(__file__).resolve().parents[2]/"scripts/backup_storage.py"
spec = importlib.util.spec_from_file_location("backup_storage", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BackupRetentionTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = pathlib.Path(self.temporary.name)
        self.root = self.base/"backups"
        self.root.mkdir()
        self.now = dt.datetime(2026, 9, 22, 15, 0, tzinfo=module.UTC)
        self.limits = module.Limits(maximum=8*1024**2, reserve=1)
        self.fake = self.base/"compose.py"
        self.fake.write_text('''import gzip,os,sys
assert sys.stdin.read() == ""
args = " ".join(sys.argv[1:])
if "pg_database_size" in args: print(1024)
elif "du -sk" in args: print("4 media")
elif "pg_dump" in args:
    sys.stdout.buffer.write(b"D"*int(os.environ.get("FAKE_DUMP_BYTES", "100")))
    sys.exit(int(os.environ.get("FAKE_DUMP_FAILURE", "0")))
elif "tar -C" in args: sys.stdout.buffer.write(gzip.compress(bytes(1024)))
else: sys.exit(9)
''')
        self.compose = [sys.executable, str(self.fake)]
        self.environment = patch.dict(os.environ, {"BACKUP_MEDIA_DIR": "", "FAKE_DUMP_BYTES": "100", "FAKE_DUMP_FAILURE": "0"})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def backup(self, created, suffix=""):
        path = self.root/(created.strftime("%Y%m%dT%H%M%SZ") + suffix)
        path.mkdir()
        for name in module.PAYLOADS:
            (path/name).write_bytes((name + path.name).encode())
        (path/"SHA256SUMS").write_text("".join(module.digest(path/name)+"  "+name+"\n" for name in sorted(module.PAYLOADS)))
        return path

    def test_daily_weekly_retention_keeps_recent_history_and_two_latest_copies(self):
        for age in range(42):
            self.backup(self.now-dt.timedelta(days=age))
        extra = self.backup(self.now+dt.timedelta(hours=1))
        valid, _ = module.inventory(self.root)
        deleted = module.retention_plan(valid, self.limits, self.now)
        retained = [row for row in valid if row[1] not in deleted]
        self.assertEqual(len(retained), 12)  # Seven days, four weeks, extra same-day copy.
        self.assertIn(extra, [path for _, path in retained])
        self.assertEqual(len({created.date() for created, _ in retained if (self.now.date()-created.date()).days < 7}), 7)
        self.assertTrue(all((self.now.date()-created.date()).days < 35 for created, _ in retained))

    def test_newest_valid_backup_survives_age_and_insufficient_capacity(self):
        latest = self.backup(self.now-dt.timedelta(days=150))
        valid, _ = module.inventory(self.root)
        self.assertEqual(module.retention_plan(valid, self.limits, self.now), [])
        with self.assertRaises(ValueError):
            module.capacity_plan(self.root, valid, 1000, module.Limits(maximum=1000, reserve=1))
        self.assertTrue(module.verify(latest))

    def test_capacity_reclaims_oldest_first_but_never_last_valid_set(self):
        old = self.backup(self.now-dt.timedelta(days=2))
        self.backup(self.now-dt.timedelta(days=1))
        latest = self.backup(self.now)
        valid, _ = module.inventory(self.root)
        size = module.directory_size(self.root)
        plan = module.capacity_plan(self.root, valid, 100, module.Limits(maximum=size+50, reserve=1))
        self.assertEqual(plan, [old])
        self.assertNotIn(latest, plan)

    def test_impossible_admission_does_not_destroy_any_history(self):
        first = self.backup(self.now-dt.timedelta(days=1))
        last = self.backup(self.now)
        valid, _ = module.inventory(self.root)
        with self.assertRaises(ValueError):
            module.capacity_plan(self.root, valid, 2000, module.Limits(maximum=1000, reserve=1))
        self.assertTrue(module.verify(first))
        self.assertTrue(module.verify(last))

    def test_corrupt_and_unrecognized_sets_are_not_pruning_candidates(self):
        good = self.backup(self.now-dt.timedelta(days=2))
        corrupt = self.backup(self.now-dt.timedelta(days=1))
        (corrupt/"database.dump").write_bytes(b"damaged")
        foreign = self.backup(self.now)
        (foreign/"unrelated.txt").write_text("preserve")
        valid, retained = module.inventory(self.root)
        self.assertEqual([path for _, path in valid], [good])
        self.assertEqual(set(retained), {corrupt.name, foreign.name})
        with self.assertRaises(ValueError):
            module.remove_sets(self.root, [foreign])
        self.assertTrue((foreign/"unrelated.txt").exists())

    def test_links_do_not_escape_the_backup_directory(self):
        outside = self.base/"important.txt"
        outside.write_text("preserve")
        (self.root/"linked").symlink_to(outside)
        with self.assertRaises(ValueError):
            with module.exclusive(self.root):
                self.fail("lock must refuse unsafe entries")
        self.assertEqual(outside.read_text(), "preserve")

    def test_oversized_manifest_is_rejected_before_loading_its_contents(self):
        backup = self.backup(self.now)
        (backup/"SHA256SUMS").write_bytes(b"x"*2048)
        with patch.object(pathlib.Path, "read_text", side_effect=AssertionError("oversized metadata must not be loaded")):
            self.assertFalse(module.verify(backup))

    def test_overlapping_run_cannot_acquire_lock(self):
        with module.exclusive(self.root):
            with self.assertRaises(ValueError):
                with module.exclusive(self.root):
                    self.fail("second lock was granted")

    def test_restore_shared_lock_prevents_backup_pruning(self):
        previous = self.backup(self.now)
        with (self.root/".backup.lock").open("a") as reader:
            module.fcntl.flock(reader, module.fcntl.LOCK_SH)
            with self.assertRaises(ValueError):
                module.run_backup(self.root, self.compose, self.limits)
        self.assertTrue(module.verify(previous))

    def test_child_keeps_lock_until_it_exits_if_parent_releases_descriptor(self):
        with module.exclusive(self.root) as descriptor:
            child = subprocess.Popen([sys.executable, "-c", "import sys;sys.stdin.read()"],
                                     stdin=subprocess.PIPE, pass_fds=(descriptor,))
        try:
            with self.assertRaises(ValueError):
                with module.exclusive(self.root):
                    self.fail("live producer lost its backup lock")
        finally:
            child.communicate(timeout=5)
        with module.exclusive(self.root):
            pass

    def test_monitor_distinguishes_active_and_interrupted_backup(self):
        with module.exclusive(self.root):
            module.write_json(self.root/".backup-status.json", {
                "status": "running", "time": dt.datetime.now(module.UTC).isoformat()})
            module.health(self.root)
        with self.assertRaises(ValueError):
            module.health(self.root)

    def test_monitor_rejects_stuck_backup_even_if_lock_is_held(self):
        with module.exclusive(self.root):
            module.write_json(self.root/".backup-status.json", {
                "status": "running", "time": (dt.datetime.now(module.UTC)-dt.timedelta(hours=2)).isoformat()})
            with self.assertRaises(ValueError):
                module.health(self.root)

    def test_monitor_reports_retained_corrupt_backup(self):
        module.write_json(self.root/".backup-status.json", {
            "status": "ok", "unverifiedRetained": ["20260921T020000Z"]})
        with self.assertRaises(ValueError):
            module.health(self.root)

    def test_stream_checks_free_reserve_before_writing(self):
        with module.exclusive(self.root) as descriptor:
            free = type("Usage", (), {"free": module.HEADROOM+10})()
            with patch.object(module.shutil, "disk_usage", return_value=free):
                with self.assertRaises(ValueError):
                    module.bounded_stream([sys.executable, "-c", "print('payload')"],
                        self.root/"output", self.root, module.Limits(maximum=1024**2, reserve=10), descriptor, "Test")
        self.assertEqual((self.root/"output").stat().st_size, 0)

    def test_success_publishes_verified_backup_then_prunes_same_day_duplicates(self):
        date = dt.datetime.now(module.UTC)-dt.timedelta(hours=2)
        originals = [self.backup(date+dt.timedelta(minutes=i)) for i in range(4)]
        completed = module.run_backup(self.root, self.compose, self.limits)
        valid, _ = module.inventory(self.root)
        self.assertTrue(module.verify(completed))
        self.assertEqual({path for _, path in valid}, {completed, originals[-1]})
        self.assertEqual(json.loads((self.root/".backup-status.json").read_text())["status"], "ok")
        self.assertFalse(list(self.root.glob(".partial-*")))

    def test_failed_producer_discards_partial_and_preserves_prior_backups(self):
        previous = self.backup(self.now)
        with patch.dict(os.environ, {"FAKE_DUMP_FAILURE": "1"}):
            with self.assertRaises(ValueError):
                module.run_backup(self.root, self.compose, self.limits)
        self.assertTrue(module.verify(previous))
        self.assertFalse(list(self.root.glob(".partial-*")))
        with self.assertRaises(ValueError):
            module.health(self.root)

    def test_larger_than_estimated_stream_aborts_without_filling_budget(self):
        previous = self.backup(self.now)
        with patch.dict(os.environ, {"FAKE_DUMP_BYTES": str(12*1024**2)}):
            with self.assertRaises(ValueError):
                module.run_backup(self.root, self.compose, self.limits)
        self.assertTrue(module.verify(previous))
        self.assertLess(module.directory_size(self.root), self.limits.maximum)
        self.assertFalse(list(self.root.glob(".partial-*")))

    def test_orphan_cleanup_is_limited_to_our_partial_layout(self):
        orphan = self.root/".partial-20260921T020000Z-deadbeef"
        orphan.mkdir()
        (orphan/"backup.json").write_text(json.dumps(module.MARKER))
        (orphan/"database.dump").write_bytes(b"incomplete")
        foreign = self.root/".partial-20260921T020000Z-12345678"
        foreign.mkdir()
        (foreign/"other-project.txt").write_text("preserve")
        completed = module.run_backup(self.root, self.compose, self.limits)
        self.assertFalse(orphan.exists())
        self.assertTrue((foreign/"other-project.txt").exists())
        self.assertTrue(module.verify(completed))

    def test_backup_is_invisible_to_readers_until_complete(self):
        stream = module.bounded_stream
        observations = []
        def during_stream(*args):
            observations.append(module.inventory(self.root)[0])
            return stream(*args)
        with patch.object(module, "bounded_stream", side_effect=during_stream):
            completed = module.run_backup(self.root, self.compose, self.limits)
        self.assertEqual(observations, [[], []])
        self.assertTrue(module.verify(completed))

    def test_cli_does_not_forward_shell_input_to_backup_producers(self):
        env = dict(os.environ, BACKUP_MAX_BYTES=str(self.limits.maximum), BACKUP_FREE_BYTES="1")
        result = subprocess.run([sys.executable, str(SCRIPT), "run", str(self.root), "--", *self.compose],
                                input="remaining caller commands\n", capture_output=True, text=True, env=env, timeout=15)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(module.inventory(self.root)[0]), 1)


if __name__ == "__main__":
    unittest.main()
