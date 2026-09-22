#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -lt 3 || $# -gt 4 ]]; then echo 'Usage: build-mobile-release.sh compile-only|signed android|ios CONFIG_JSON [IOS_EXPORT_OPTIONS_PLIST]' >&2; exit 2; fi
absolute_path() { python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$1"; }
mode=$1
platform=$2
config=$(absolute_path "$3")
python3 scripts/validate-mobile-config.py "$config" "$mode" "$platform"
: "${FLUTTER_BIN:=flutter}"
if [[ "$platform" == android ]]; then
  if [[ "$mode" == signed ]]; then
    : "${BIOBALANCE_KEYSTORE:?Provide the existing release keystore}"
    : "${BIOBALANCE_KEYSTORE_PASSWORD:?Provide keystore password}"
    : "${BIOBALANCE_KEY_ALIAS:?Provide key alias}"
    : "${BIOBALANCE_KEY_PASSWORD:?Provide key password}"
    export BIOBALANCE_KEYSTORE=$(absolute_path "$BIOBALANCE_KEYSTORE")
    test -f "$BIOBALANCE_KEYSTORE"
  elif [[ -n ${BIOBALANCE_KEYSTORE:-} ]]; then
    echo 'Compilation-only artifacts must not use a release keystore' >&2; exit 1
  fi
else
  [[ $(uname -s) == Darwin ]] || { echo 'iOS requires macOS/Xcode' >&2; exit 1; }
  if [[ "$mode" == signed ]]; then
    [[ $# == 4 && -f apps/mobile/ios/Flutter/Signing.xcconfig ]] || { echo 'Supply Signing.xcconfig and an export-options plist for the existing Apple team' >&2; exit 1; }
    export_options=$(absolute_path "$4")
    test -f "$export_options"
  fi
fi
# Keep native Universal Links and the Dart allowlist on the same configured host.
if [[ "$platform" == ios ]]; then
  python3 - "$config" <<'PYLINK'
import json,pathlib,sys
host=json.load(open(sys.argv[1])).get('AUTH_LINK_HOST') or 'account-links.invalid'
pathlib.Path('apps/mobile/ios/Flutter/AccountLinks.xcconfig').write_text('AUTH_LINK_HOST = '+host+'\n')
PYLINK
fi
output="$PWD/.artifacts/releases/builds/$(date -u +%Y%m%dT%H%M%SZ)-$platform-$mode"
mkdir -p "$output"
cp "$config" "$output/public-mobile-config.json"
(
  cd apps/mobile
  "$FLUTTER_BIN" pub get --enforce-lockfile
  if [[ "$platform" == android ]]; then
    "$FLUTTER_BIN" build apk --release --target lib/main.dart --dart-define-from-file="$config"
    "$FLUTTER_BIN" build appbundle --release --target lib/main.dart --dart-define-from-file="$config"
    cp build/app/outputs/flutter-apk/app-release.apk "$output/biobalance-$mode.apk"
    cp build/app/outputs/bundle/release/app-release.aab "$output/biobalance-$mode.aab"
  elif [[ "$mode" == compile-only ]]; then
    "$FLUTTER_BIN" build ios --release --no-codesign --target lib/main.dart --dart-define-from-file="$config"
    ditto build/ios/iphoneos/Runner.app "$output/Runner-unsigned.app"
  else
    "$FLUTTER_BIN" build ipa --release --target lib/main.dart --dart-define-from-file="$config" --export-options-plist="$export_options"
    ditto build/ios/archive/Runner.xcarchive "$output/Runner.xcarchive"
    cp build/ios/ipa/*.ipa "$output/"
  fi
)
if [[ "$platform" == android ]]; then
  sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
  [[ -n "$sdk" ]] || { echo 'ANDROID_HOME is required to verify the APK signature' >&2; exit 1; }
  python3 scripts/verify-android-binary.py "$output/biobalance-$mode.apk" "$sdk" > "$output/native-alignment.txt"
  apksigner=$(find "$sdk/build-tools" -name apksigner -type f | sort -V | tail -n 1)
  if [[ "$mode" == signed ]]; then
    "$apksigner" verify --verbose --print-certs "$output/biobalance-signed.apk" > "$output/apk-signature.txt"
    jarsigner -verify "$output/biobalance-signed.aab" > "$output/aab-signature.txt"
    # jarsigner can exit zero for unsigned archives; require actual signing entries too.
    python3 - "$output/biobalance-signed.aab" <<'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    assert any(n.startswith('META-INF/') and n.endswith(('.RSA','.DSA','.EC')) for n in z.namelist()), 'Unsigned AAB'
PY
  else
    if "$apksigner" verify "$output/biobalance-compile-only.apk" > "$output/apk-signature.txt" 2>/dev/null; then echo 'Unexpected signature on compilation-only APK' >&2; exit 1; fi
    python3 - "$output/biobalance-compile-only.apk" <<'PYAPK'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    assert z.testzip() is None and 'AndroidManifest.xml' in z.namelist(), 'Invalid APK archive'
    assert not any(n.startswith('META-INF/') and n.endswith(('.RSA','.DSA','.EC')) for n in z.namelist()), 'Unexpected APK v1 signature'
PYAPK
    printf 'Unsigned APK verified as a valid archive; no release signing identity was used.\n' > "$output/apk-signature.txt"
    python3 - "$output/biobalance-compile-only.aab" <<'PY'
import sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    assert not any(n.startswith('META-INF/') and n.endswith(('.RSA','.DSA','.EC')) for n in z.namelist()), 'Unexpected signed AAB'
PY
  fi
fi
python3 scripts/release-manifest.py "$output" "$mode" "$platform"
printf 'Artifacts: %s\n' "$output"
