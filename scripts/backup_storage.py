#!/usr/bin/env python3
"""Bounded, serialized local backups with checksum-aware retention.

Only timestamped BioBalance backup sets with the expected files are eligible
for deletion. The newest checksum-valid set is always protected.
"""
import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import uuid

UTC = dt.timezone.utc
GIB = 1024**3
HEADROOM = 65536
PAYLOADS = {"database.dump", "media.tar.gz"}
BACKUP_NAME = re.compile(r"^(\d{8}T\d{6}Z)(?:-[a-f0-9]{8})?$")
MARKER = {"format": "biobalance-local-backup", "version": 1}


class Limits:
    def __init__(self, maximum=4*GIB, reserve=10*GIB, daily=7, weekly=4):
        if maximum <= 0 or reserve <= 0 or daily < 1 or weekly < 0:
            raise ValueError("Backup limits must be positive; weekly retention may be zero")
        self.maximum, self.reserve = maximum, reserve
        self.daily, self.weekly = daily, weekly

    @classmethod
    def environment(cls):
        return cls(int(os.environ.get("BACKUP_MAX_BYTES", 4*GIB)),
                   int(os.environ.get("BACKUP_FREE_BYTES", 10*GIB)),
                   int(os.environ.get("BACKUP_DAILY_DAYS", 7)),
                   int(os.environ.get("BACKUP_WEEKLY_WEEKS", 4)))


def directory_size(root):
    """Never follow links to unrelated server data."""
    total = 0
    for current, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            info = (pathlib.Path(current)/name).lstat()
            if stat.S_ISLNK(info.st_mode):
                raise ValueError("Symbolic link in backup directory; manual review required")
            if stat.S_ISREG(info.st_mode):
                total += info.st_size
            elif not stat.S_ISDIR(info.st_mode):
                raise ValueError("Unsupported backup entry; manual review required")
    return total


def check(directory, expected_bytes, *, maximum=4*GIB, reserve=10*GIB):
    if expected_bytes <= 0 or maximum <= 0 or reserve <= 0:
        raise ValueError("Backup limits must be positive")
    if directory_size(directory) + expected_bytes > maximum:
        raise ValueError("Backup capacity reached while preserving the newest valid backup")
    if shutil.disk_usage(directory).free < expected_bytes + reserve:
        raise ValueError("Insufficient backup disk reserve; operational data must remain writable")


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024*1024), b""):
            result.update(chunk)
    return result.hexdigest()


def sync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w") as output:
        json.dump(value, output, sort_keys=True)
        output.write("\n")
        output.flush()
        os.fsync(output.fileno())
    temporary.replace(path)
    sync_directory(path.parent)


@contextlib.contextmanager
def exclusive(root):
    root = pathlib.Path(root)
    if not root.is_absolute() or root.is_symlink() or root.resolve() == pathlib.Path("/"):
        raise ValueError("Use an absolute, dedicated, non-symlink backup directory")
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(root/".backup.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError("Another backup or retention run already holds the lock") from None
        directory_size(root)
        yield fd
    finally:
        os.close(fd)


def expected_layout(path, partial=False):
    if path.is_symlink() or not path.is_dir():
        return False
    names = {p.name for p in path.iterdir()}
    allowed = PAYLOADS | {"SHA256SUMS", "backup.json"}
    if not names.issubset(allowed) or any(not p.is_file() or p.is_symlink() for p in path.iterdir()):
        return False
    if partial and not names:
        return True
    if partial or "backup.json" in names:
        try:
            if (path/"backup.json").stat().st_size > 256:
                return False
            if json.loads((path/"backup.json").read_text()) != MARKER:
                return False
        except (OSError, ValueError):
            return False
    return partial or (PAYLOADS | {"SHA256SUMS"}) <= names


def verify(path):
    if not expected_layout(path):
        return False
    try:
        if (path/"SHA256SUMS").stat().st_size > 1024:
            return False
        rows = (path/"SHA256SUMS").read_text().splitlines()
        pairs = [re.fullmatch(r"([a-f0-9]{64})  (database\.dump|media\.tar\.gz)", row) for row in rows]
        if len(pairs) != 2 or not all(pairs) or {pair[2] for pair in pairs} != PAYLOADS:
            return False
        return all((path/pair[2]).stat().st_size > 0 and digest(path/pair[2]) == pair[1] for pair in pairs)
    except (OSError, ValueError):
        return False


def inventory(root):
    valid, retained = [], []
    for path in sorted(root.iterdir()):
        match = BACKUP_NAME.fullmatch(path.name)
        if not match:
            continue
        try:
            created = dt.datetime.strptime(match[1], "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
        except ValueError:
            retained.append(path.name)
            continue
        if verify(path):
            valid.append((created, path))
        else:
            retained.append(path.name)
    valid.sort(key=lambda row: (row[0], row[1].name), reverse=True)
    return valid, retained


def retention_plan(valid, limits, now):
    # Prefer two recent copies, including manual runs on the same calendar day.
    keep = {path for _, path in valid[:2]}
    days, weeks = set(), set()
    for created, path in valid:
        age = (now.date() - created.date()).days
        week = created.isocalendar()[:2]
        if age < 0:
            keep.add(path)
        elif age < limits.daily and created.date() not in days:
            days.add(created.date())
            keep.add(path)
        elif limits.daily <= age < limits.daily + 7*limits.weekly and week not in weeks and len(weeks) < limits.weekly:
            weeks.add(week)
            keep.add(path)
    return [path for _, path in reversed(valid) if path not in keep]


def capacity_plan(root, valid, expected, limits):
    used, free = directory_size(root), shutil.disk_usage(root).free
    needed = max(0, used + expected - limits.maximum, expected + limits.reserve - free)
    candidates, released = [], 0
    for _, path in reversed(valid[1:]):
        if released >= needed:
            break
        candidates.append(path)
        released += directory_size(path)
    if released < needed:
        raise ValueError("Cannot fit another backup without using the disk reserve or newest valid copy; increase capacity")
    return candidates


def remove_sets(root, paths, *, partial=False):
    removed = []
    for path in paths:
        if path.parent != root or not expected_layout(path, partial=partial):
            raise ValueError("Refusing to remove an unrecognized backup set")
        # No recursive deletion: recognized sets contain only these regular files.
        for item in path.iterdir():
            item.unlink()
        path.rmdir()
        removed.append(path.name)
    if removed:
        sync_directory(root)
        print(f"Removed {len(removed)} backup sets: " + ", ".join(removed[:20]), flush=True)
    return removed


def remove_orphans(root):
    candidates = [path for path in root.iterdir()
                  if path.name.startswith(".partial-") and BACKUP_NAME.fullmatch(path.name[9:])
                  and expected_layout(path, partial=True)]
    return remove_sets(root, candidates, partial=True)


def bounded_stream(command, target, root, limits, lock_fd, label):
    """Abort and reap the producer before its stream crosses either limit."""
    base = directory_size(root)
    written = 0
    process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, pass_fds=(lock_fd,))
    try:
        with target.open("xb") as output:
            while True:
                chunk = process.stdout.read(1024*1024)
                if not chunk:
                    break
                if base + written + len(chunk) + HEADROOM > limits.maximum:
                    raise ValueError(label + " exceeded the backup storage budget")
                if shutil.disk_usage(root).free < len(chunk) + limits.reserve + HEADROOM:
                    raise ValueError(label + " reached the operational free-space reserve")
                output.write(chunk)
                written += len(chunk)
            output.flush()
            os.fsync(output.fileno())
        if process.wait(timeout=30) != 0 or written == 0:
            raise ValueError(label + " producer failed or returned an empty file")
    finally:
        process.stdout.close()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()


def measure(command, lock_fd):
    value = subprocess.check_output(command, stdin=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                    pass_fds=(lock_fd,), timeout=120).decode().strip()
    if not value:
        raise ValueError("Cannot measure a backup source")
    result = int(value.split()[0])
    if result <= 0:
        raise ValueError("Cannot measure a backup source")
    return result


def run_backup(root, compose, limits):
    with exclusive(root) as lock_fd:
        pending = None
        try:
            write_json(root/".backup-status.json", {"status": "running", "time": dt.datetime.now(UTC).isoformat()})
            remove_orphans(root)
            valid, retained = inventory(root)
            database_size = measure(compose + ["exec", "-T", "postgres", "sh", "-c",
                'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT pg_database_size(current_database())"'], lock_fd)
            media_source = os.environ.get("BACKUP_MEDIA_DIR")
            if media_source:
                if root.resolve().is_relative_to(pathlib.Path(media_source).resolve()):
                    raise ValueError("Backup directory must not be inside its media source")
                media_size = measure(["du", "-sk", media_source], lock_fd)*1024
                media_command = ["tar", "-C", media_source, "-czf", "-", "."]
            else:
                media_size = measure(compose + ["exec", "-T", "api1", "du", "-sk", "/var/lib/biobalance/media"], lock_fd)*1024
                media_command = compose + ["exec", "-T", "api1", "tar", "-C", "/var/lib/biobalance/media", "-czf", "-", "."]
            estimate = database_size*2 + media_size + 4194304 + HEADROOM
            removed = remove_sets(root, capacity_plan(root, valid, estimate, limits))
            check(root, estimate, maximum=limits.maximum, reserve=limits.reserve)
            name = dt.datetime.now(UTC).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
            pending = root/(".partial-" + name)
            pending.mkdir(mode=0o700)
            # This small ownership marker precedes all payload writes.
            with (pending/"backup.json").open("x") as marker:
                json.dump(MARKER, marker)
                marker.flush()
                os.fsync(marker.fileno())
            bounded_stream(compose + ["exec", "-T", "postgres", "sh", "-c",
                'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom'],
                pending/"database.dump", root, limits, lock_fd, "Database dump")
            bounded_stream(media_command, pending/"media.tar.gz", root, limits, lock_fd, "Media archive")
            with (pending/"SHA256SUMS").open("x") as sums:
                for filename in sorted(PAYLOADS):
                    sums.write(digest(pending/filename) + "  " + filename + "\n")
                sums.flush()
                os.fsync(sums.fileno())
            if not verify(pending):
                raise ValueError("New backup failed checksum verification")
            sync_directory(pending)
            completed = root/name
            pending.rename(completed)
            pending = None
            sync_directory(root)
            valid = [(created, path) for created, path in valid if path.exists()]
            valid.insert(0, (dt.datetime.now(UTC), completed))
            removed += remove_sets(root, retention_plan(valid, limits, dt.datetime.now(UTC)))
            write_json(root/".backup-status.json", {"status": "ok", "time": dt.datetime.now(UTC).isoformat(),
                "latest": name, "removed": removed[:100], "removedCount": len(removed),
                "unverifiedRetained": retained[:100], "unverifiedRetainedCount": len(retained),
                "usedBytes": directory_size(root), "maximumBytes": limits.maximum})
            print("Local backup created and verified: " + str(completed), flush=True)
            return completed
        except Exception as error:
            if pending is not None and pending.exists() and expected_layout(pending, partial=True):
                remove_sets(root, [pending], partial=True)
            write_json(root/".backup-status.json", {"status": "failed", "time": dt.datetime.now(UTC).isoformat(),
                "error": str(error) if isinstance(error, ValueError) else type(error).__name__})
            raise


def health(root):
    status_file = root/".backup-status.json"
    if status_file.exists():
        if status_file.is_symlink() or status_file.stat().st_size > HEADROOM:
            raise ValueError("Unsafe backup status file")
        state = json.loads(status_file.read_text())
        if state.get("status") == "running":
            age = (dt.datetime.now(UTC)-dt.datetime.fromisoformat(state["time"])).total_seconds()
            descriptor = os.open(root/".backup.lock", os.O_RDONLY | os.O_NOFOLLOW)
            try:
                try:
                    fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    if 0 <= age <= 3900:
                        print("PASS: managed backup is currently running within its time limit")
                        return
                raise ValueError("Backup was interrupted or exceeded its time limit; inspect biobalance-backup.service")
            finally:
                os.close(descriptor)
        if state.get("status") != "ok":
            raise ValueError("The last backup attempt failed; inspect biobalance-backup.service")
        if state.get("unverifiedRetained"):
            raise ValueError("Unrecognized or corrupt backup sets were retained for manual review")
    print("PASS: last managed backup attempt has no recorded failure")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["run", "plan", "health"])
    parser.add_argument("directory", type=pathlib.Path)
    parser.add_argument("compose", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    limits = Limits.environment()
    if args.action == "health":
        return health(args.directory)
    if args.action == "plan":
        with exclusive(args.directory):
            valid, retained = inventory(args.directory)
            print(json.dumps({"valid": [path.name for _, path in valid], "unverifiedRetained": retained,
                "wouldRemoveAfterSuccessfulBackup": [path.name for path in retention_plan(valid, limits, dt.datetime.now(UTC))],
                "usedBytes": directory_size(args.directory), "maximumBytes": limits.maximum,
                "freeReserveBytes": limits.reserve, "dailyDays": limits.daily, "weeklyWeeks": limits.weekly}, indent=2))
        return
    compose = args.compose[1:] if args.compose[:1] == ["--"] else args.compose
    if not compose:
        raise ValueError("Compose command is required")
    run_backup(args.directory, compose, limits)


if __name__ == "__main__":
    os.umask(0o077)
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        sys.exit("Backup operation failed: " + (str(error) if isinstance(error, ValueError) else type(error).__name__))
