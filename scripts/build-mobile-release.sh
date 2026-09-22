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
if [[ "$mode" == signed && -n $(git status --porcelain) ]]; then
  echo 'Commit and review the complete checkout before producing signed release artifacts.' >&2
  exit 1
fi
if [[ "$platform" == android ]]; then
  if [[ "$mode" == signed ]]; then
    : "${BIOBALANCE_KEYSTORE:?Provide the existing release keystore}"
    : "${BIOBALANCE_KEYSTORE_PASSWORD:?Provide keystore password}"
    : "${BIOBALANCE_KEY_ALIAS:?Provide key alias}"
    : "${BIOBALANCE_KEY_PASSWORD:?Provide key password}"
    export BIOBALANCE_KEYSTORE=$(absolute_path "$BIOBALANCE_KEYSTORE")
    test -f "$BIOBALANCE_KEYSTORE"
    python3 scripts/verify-android-signer.py key BIOBALANCE_ config/signing/android-certificates.json
    python3 scripts/verify-android-signer.py key BIOBALANCE_UPLOAD_ config/signing/android-certificates.json
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
stamp=$(date -u +%Y%m%dT%H%M%SZ)
output="$PWD/.artifacts/releases/builds/$stamp-$platform-$mode"
# Symbol files are private operational artifacts, never included in distribution packages.
symbols="$PWD/.artifacts/private-symbols/$stamp-$platform-$mode"
umask 077
mkdir -p "$symbols"
export BIOBALANCE_BUILD_MODE="$mode"
if [[ "$mode" == signed ]]; then
  # Do not retain signing credentials in a reusable Gradle daemon after the build.
  export GRADLE_OPTS="${GRADLE_OPTS:-} -Dorg.gradle.daemon=false"
fi
mkdir -p "$output"
cp "$config" "$output/public-mobile-config.json"
(
  cd apps/mobile
  "$FLUTTER_BIN" pub get --enforce-lockfile
  if [[ "$platform" == android ]]; then
    "$FLUTTER_BIN" build apk --release --obfuscate --split-debug-info="$symbols/apk" --target lib/main.dart --dart-define-from-file="$config"
    cp build/app/outputs/flutter-apk/app-release.apk "$output/biobalance-$mode.apk"
    if [[ "$mode" == signed ]]; then
      export BIOBALANCE_KEYSTORE="$BIOBALANCE_UPLOAD_KEYSTORE"
      export BIOBALANCE_KEYSTORE_PASSWORD="$BIOBALANCE_UPLOAD_KEYSTORE_PASSWORD"
      export BIOBALANCE_KEY_ALIAS="$BIOBALANCE_UPLOAD_KEY_ALIAS"
      export BIOBALANCE_KEY_PASSWORD="$BIOBALANCE_UPLOAD_KEY_PASSWORD"
    fi
    "$FLUTTER_BIN" build appbundle --release --obfuscate --split-debug-info="$symbols/aab" --target lib/main.dart --dart-define-from-file="$config"
    cp build/app/outputs/bundle/release/app-release.aab "$output/biobalance-$mode.aab"
  elif [[ "$mode" == compile-only ]]; then
    "$FLUTTER_BIN" build ios --release --obfuscate --split-debug-info="$symbols" --no-codesign --target lib/main.dart --dart-define-from-file="$config"
    ditto build/ios/iphoneos/Runner.app "$output/Runner-unsigned.app"
  else
    "$FLUTTER_BIN" build ipa --release --obfuscate --split-debug-info="$symbols" --target lib/main.dart --dart-define-from-file="$config" --export-options-plist="$export_options"
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
    python3 scripts/verify-android-signer.py apk "$output/biobalance-signed.apk" "$apksigner" "$BIOBALANCE_CERT_SHA256" > "$output/apk-signature.txt"
    java scripts/VerifyAndroidBundle.java "$output/biobalance-signed.aab" "$BIOBALANCE_UPLOAD_CERT_SHA256" > "$output/aab-signature.txt"
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
if [[ "$platform" == ios && "$mode" == signed ]]; then
  team=$(python3 - <<'PYTEAM'
import pathlib,re
text=pathlib.Path('apps/mobile/ios/Flutter/Signing.xcconfig').read_text()
match=re.search(r'^DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]{10})\s*$',text,re.M)
if not match: raise SystemExit('Configure the existing Apple team')
print(match[1])
PYTEAM
)
  for ipa in "$output"/*.ipa; do
    python3 scripts/verify-ios-signature.py "$ipa" "$team" > "$output/ios-signature.txt"
  done
fi

python3 scripts/release-manifest.py "$output" "$mode" "$platform"
printf 'Artifacts: %s\n' "$output"
