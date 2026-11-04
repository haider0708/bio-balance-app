#!/usr/bin/env bash
# Build the signed Android app and publish it as the download everyone gets: https://api.galylio.com/download/biobalance.apk
# Usage: scripts/publish-apk.sh       (needs Flutter, the Android SDK, the release key in ~/.biobalance/signing/,
#         `ssh go2code` with sudo, and a clean checkout equal to GitHub's main: see scripts/deploy-guard.sh)
# The same file is what the welcome message and the install page link to. It carries the version in pubspec.yaml and
# is signed with the same key as the Google Play build, so a phone can update from one to the other. The previous
# file is kept on the server (/opt/biobalance-downloads/previous) for a rollback.
set -euo pipefail
host=${DEPLOY_HOST:-go2code}
url=${APK_URL:-https://api.galylio.com/download/biobalance.apk}
cd "$(dirname "$0")/.."
source scripts/deploy-guard.sh
source ~/.biobalance/signing/env.sh
guard_start apk "$host"
cd apps/mobile

version=$(sed -n 's/^version: *//p' pubspec.yaml)
name=${version%+*}
build=${version#*+}
echo "== Checks ($version)"
flutter pub get --enforce-lockfile >/dev/null
flutter analyze | tail -1
flutter test | tail -1

echo "== Building the signed APK"
flutter build apk --release | tail -2
apk=build/app/outputs/flutter-apk/app-release.apk
tools=$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/* | sort -V | tail -1)

echo "== Checking what was built"
badging=$("$tools/aapt2" dump badging "$apk")
echo "$badging" | grep -q "package: name='tn.biobalance.app' versionCode='$build' versionName='$name'" \
  || { echo "The APK is not tn.biobalance.app $version." >&2; exit 1; }
built=$("$tools/apksigner" verify --print-certs "$apk" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')
expected=$(keytool -list -keystore "$BIOBALANCE_KEYSTORE" -alias "$BIOBALANCE_KEY_ALIAS" -storepass "$BIOBALANCE_KEYSTORE_PASSWORD" 2>/dev/null \
  | sed -n 's/^Certificate fingerprint (SHA-256): //p' | tr -d ':' | tr 'A-F' 'a-f')
[ -n "$built" ] && [ "$built" = "$expected" ] || { echo "The APK is not signed with the release key." >&2; exit 1; }
sha=$(shasum -a 256 "$apk" | cut -d' ' -f1)
bytes=$(wc -c <"$apk" | tr -d ' ')

echo "== Uploading to $host"
stage="/tmp/biobalance-apk.$$"
ssh "$host" "mkdir -p $stage"
rsync -a "$apk" "$host:$stage/biobalance.apk"
printf '{"version":"%s","build":%s,"bytes":%s,"sha256":"%s","publishedAt":"%s"}\n' "$name" "$build" "$bytes" "$sha" "$(date -u +%FT%TZ)" \
  | ssh "$host" "cat >$stage/latest.json"
ssh "$host" "sudo mkdir -p /opt/biobalance-downloads/previous \
  && { [ ! -f /opt/biobalance-downloads/biobalance.apk ] || sudo cp -p /opt/biobalance-downloads/biobalance.apk /opt/biobalance-downloads/previous/biobalance.apk; } \
  && sudo chown root:root $stage/* && sudo chmod 644 $stage/* \
  && sudo mv $stage/biobalance.apk /opt/biobalance-downloads/biobalance.apk \
  && sudo mv $stage/latest.json /opt/biobalance-downloads/latest.json && rmdir $stage"

echo "== Checking the public download"
got=$(curl -fsSL -m 300 "$url" | shasum -a 256 | cut -d' ' -f1)
[ "$got" = "$sha" ] || { echo "The download does not match the file that was uploaded." >&2; exit 1; }
echo "Live: $url ($version, $((bytes / 1048576)) MB, sha256 ${sha:0:12}…)"
guard_done
