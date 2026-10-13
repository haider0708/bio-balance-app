#!/usr/bin/env bash
# Keep a copy of the server's nightly backups on this machine, so they survive losing the server.
# Usage: scripts/pull-backups.sh            copy the newest complete backup (checked against its
#                                          checksums) to ~/.biobalance/backups, keep the last 14
#        scripts/pull-backups.sh --install  on a Mac, run it every day at 09:30 (and after a sleep
#                                          that missed it); its log is ~/.biobalance/backups/pull.log
# Needs `ssh go2code` (a key without a passphrase prompt) and sudo rights there. The copies hold
# personal data: keep them on an encrypted disk (FileVault on a Mac).
set -euo pipefail
host=${BACKUP_HOST:-go2code}
dest=${BACKUP_DIR:-$HOME/.biobalance/backups}
keep=${BACKUP_KEEP:-14}
here=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" = "--install" ]; then
  [ "$(uname)" = Darwin ] || { echo "--install is for a Mac (use cron elsewhere)." >&2; exit 1; }
  mkdir -p "$dest" && chmod 700 "$dest"
  mkdir -p ~/Library/LaunchAgents
  plist=~/Library/LaunchAgents/tn.biobalance.pull-backups.plist
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>tn.biobalance.pull-backups</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$here/pull-backups.sh</string></array>
  <key>StartCalendarInterval</key><dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>30</integer></dict>
  <key>StandardOutPath</key><string>$dest/pull.log</string>
  <key>StandardErrorPath</key><string>$dest/pull.log</string>
</dict></plist>
EOF
  launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$plist"
  echo "Installed: every day at 09:30, log in $dest/pull.log"
  exit 0
fi

mkdir -p "$dest" && chmod 700 "$dest"
echo "== $(date '+%F %T') pulling from $host"
# The newest backup that finished (a backup in progress has no checksum file yet).
latest=$(ssh "$host" "sudo sh -c 'ls -1d /srv/biobalance-backups/2*/SHA256SUMS 2>/dev/null | sort | tail -1'")
[ -n "$latest" ] || { echo "No finished backup on the server." >&2; exit 1; }
name=$(basename "$(dirname "$latest")")
if [ -d "$dest/$name" ]; then
  echo "Already here: $name"
else
  incoming="$dest/.incoming-$name"
  rm -rf "$incoming" && mkdir -p "$incoming"
  ssh "$host" "sudo tar -C /srv/biobalance-backups/$name -cf - ." | tar -C "$incoming" -xf -
  if ! (cd "$incoming" && shasum -a 256 -c SHA256SUMS >/dev/null); then
    rm -rf "$incoming"
    echo "The copy does not match its checksums: discarded." >&2
    exit 1
  fi
  chmod -R go-rwx "$incoming"
  mv "$incoming" "$dest/$name"
  echo "Copied and checked: $name ($(du -sh "$dest/$name" | cut -f1))"
fi
# Keep the newest $keep.
ls -1d "$dest"/2*/ 2>/dev/null | sort -r | tail -n +$((keep + 1)) | while read -r old; do
  rm -rf "$old" && echo "Removed old copy: $(basename "$old")"
done
