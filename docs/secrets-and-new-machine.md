# Secrets, and setting up a new machine

No secret value is in this file or anywhere in the repository (it is public). This says **where they are** and **how to put a machine back to work**.

## Where the secrets live

On the server, `/etc/biobalance/` (root only, mode 700; files 600). Reach it with `ssh go2code` and `sudo`.

| What | Where |
|---|---|
| The server's own secrets (database, sign-in encryption key, SMTP, push keys, store links) | `/etc/biobalance/backend.env` (the only copy that matters; `MFA_ENCRYPTION_KEY` loss locks the admin's authenticator) |
| First admin created at set-up | `/etc/biobalance/admin/initial-admin.json` |
| **Android signing key** (upload key of Google Play, also signs the direct APK), its password and the Gradle variables | `/etc/biobalance/secrets/android/` (`biobalance-release.jks`, `store.pass`, `env.sh`) |
| **App Store Connect API keys** (upload builds, TestFlight, listing) and their ids | `/etc/biobalance/secrets/apple/` (`AuthKey_*.p8`, `env.sh`) |
| The admin's authenticator secret (2-step sign-in) | `/etc/biobalance/secrets/admin/` |
| The old hand-off notes with the reviewer passwords, the iOS team id file, small helper scripts | `/etc/biobalance/secrets/other/` |

The copy was checked file by file (SHA-256) against the originals on 2026-11-05. The server's nightly backups are in `/srv/biobalance-backups` (02:30 UTC).

**One copy is not enough for the Android key.** If the keystore is lost, Google Play cannot be updated any more. Keep a second copy outside the server (a password manager or an encrypted USB key): `scp`/`sudo cat` it out of `/etc/biobalance/secrets/android/` once and store it with its password.

## What could not be moved (and why)

- **SSH keys** (`~/.ssh/go2code_mac`): never copied between machines. Each machine makes its own: `ssh-keygen -t ed25519`, then add the public key to `~ubuntu/.ssh/authorized_keys` on the server (from a machine that can already get in, or from the hosting provider's console).
- **GitHub login** (`gh auth login`) and the **Apple ID / Xcode signing**: personal to the machine's user. Xcode's automatic signing uses the App Store Connect API key (`apple/`), so no certificate has to be carried over.
- **Cloudflare, Google Play Console, Firebase, the domain registrar**: the owner's own web logins.

## Setting up a new machine

1. `git clone https://github.com/haider0708/bio-balance-app.git`, then read `CLAUDE.md`.
2. Make an SSH key and get it authorized on the server (above), then test `ssh go2code` (an entry in `~/.ssh/config`: host `go2code`, the server's address, user `ubuntu`).
3. Bring the keys back, to the folders the scripts expect:
   ```bash
   mkdir -p ~/.biobalance/signing ~/.biobalance/appstore
   ssh go2code 'sudo tar -C /etc/biobalance/secrets -cf - android apple' | tar -C ~/.biobalance -xf -
   mv ~/.biobalance/android/* ~/.biobalance/signing/ && mv ~/.biobalance/apple/* ~/.biobalance/appstore/ && rmdir ~/.biobalance/android ~/.biobalance/apple
   chmod -R go-rwx ~/.biobalance
   ```
   The `env.sh` files may name the old machine's home folder; the scripts rewrite `/home/<user>/` to the current home (see `scripts/publish-apk.sh`).
4. iPhone: `bash scripts/mac-setup.sh`, then `docs/app-store-steps.md`. Android and web: Flutter 3.47.5 and the Android SDK (`docs/mobile-release.md`).
5. Test: `ssh go2code true`, `node scripts/testflight.mjs status` (after `source ~/.biobalance/appstore/env.sh`), `cd apps/mobile && flutter analyze && flutter test`.

## Before selling or giving away a machine

Do these on the machine, in this order. Nothing here touches the server.

1. Everything is pushed (`git status`, `git log origin/main..`), and the server copy of the keys is checked (above).
2. Keep one more copy of the Android keystore and its password outside the server.
3. Stop the daily backup pull: `launchctl unload ~/Library/LaunchAgents/tn.biobalance.pull-backups.plist && rm ~/Library/LaunchAgents/tn.biobalance.pull-backups.plist`. **The backups then exist only on the server** (`/srv/biobalance-backups`): decide where a second copy goes (another machine running `scripts/pull-backups.sh`, or a cloud bucket).
4. Remove the machine's key from the server: delete its line (comment `biobalance-mac`) from `~ubuntu/.ssh/authorized_keys`. **Only after the new machine's key is in**, or nobody can deploy.
5. Sign out: `gh auth logout`, Xcode > Settings > Accounts (remove the Apple ID), the browser sign-ins (Play Console, App Store Connect, Cloudflare), `claude` logout.
6. Delete the local secrets: `rm -rf ~/.biobalance ~/BIOBALANCE/.local-credentials-v2 ~/BIOBALANCE/mac-handoff-private.md ~/BIOBALANCE/apps/mobile/ios/Flutter/Signing.xcconfig`, and empty the Trash.
7. Finally erase the Mac (System Settings > General > Transfer or Reset > Erase All Content and Settings), which also removes the Keychain.
