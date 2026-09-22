#!/usr/bin/env python3
"""Refuse a backup before it consumes the operational disk reserve. Never delete backups."""
import os
import pathlib
import shutil
import sys


def check(directory, expected_bytes, *, maximum=64 * 1024**3, reserve=10 * 1024**3):
    root = pathlib.Path(directory)
    if expected_bytes <= 0 or maximum <= 0 or reserve <= 0:
        raise ValueError("Backup limits must be positive")
    used = sum(p.stat().st_size for p in root.rglob("*") if p.is_file())
    if used + expected_bytes > maximum:
        raise ValueError("Backup capacity reached; archive or remove verified old backups before retrying")
    if shutil.disk_usage(root).free < expected_bytes + reserve:
        raise ValueError("Insufficient backup disk reserve; operational data must remain writable")


if __name__ == "__main__":
    try:
        check(sys.argv[1], int(sys.argv[2]),
              maximum=int(os.environ.get("BACKUP_MAX_BYTES", 64 * 1024**3)),
              reserve=int(os.environ.get("BACKUP_FREE_BYTES", 10 * 1024**3)))
    except (ValueError, IndexError, OSError) as error:
        sys.exit(f"Backup admission failed: {error}")
