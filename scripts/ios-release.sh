#!/usr/bin/env bash
# Build the iPhone app for the App Store and (with --upload) send it to App Store Connect / TestFlight.
# Usage: scripts/ios-release.sh [--upload]      (on the Mac; version = `version:` in apps/mobile/pubspec.yaml)
# Signing goes through the App Store Connect API team key in ~/.biobalance/appstore/env.sh (ASC_KEY_ID,
# ASC_ISSUER_ID, ASC_KEY_PATH): no Apple ID in Xcode. The team has no registered device and no free
# distribution certificate, so the archive is built unsigned, signed here with this Mac's development
# certificate and the app's real entitlements (push), and Apple's cloud signing turns it into an App Store
# build at export. The script refuses a result without the production push entitlement.
set -euo pipefail
cd "$(dirname "$0")/../apps/mobile"
source ~/.biobalance/appstore/env.sh
export LANG=en_US.UTF-8 SSL_CERT_FILE=/etc/ssl/cert.pem
destination=export
[ "${1:-}" = "--upload" ] && destination=upload
team=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' ios/Flutter/Signing.xcconfig)
bundle=tn.biobalance.app
archive=build/ios/archive/Runner.xcarchive
app=$archive/Products/Applications/Runner.app
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
key=(-allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "== Checks"
flutter pub get --enforce-lockfile >/dev/null
flutter analyze | tail -1
flutter test | tail -1

echo "== Archive ($(sed -n 's/^version: //p' pubspec.yaml))"
flutter build ios --release --config-only >/dev/null
rm -rf "$archive"
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= archive >"$work/archive.log" 2>&1 ||
  { grep -E 'error:' "$work/archive.log" | sort -u; exit 1; }

echo "== Sign the archive with the app's entitlements"
identity=$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')
[ -n "$identity" ] || { echo "No valid Apple Development certificate in the keychain." >&2; exit 1; }
cp ios/Runner/Runner.entitlements "$work/app.entitlements"
/usr/libexec/PlistBuddy -c "Add :application-identifier string $team.$bundle" \
  -c "Add :com.apple.developer.team-identifier string $team" -c "Add :get-task-allow bool true" \
  "$work/app.entitlements" >/dev/null
shopt -s nullglob
for code in "$app"/Frameworks/*.framework "$app"/Frameworks/*.dylib; do
  codesign -f -s "$identity" --timestamp=none --generate-entitlement-der "$code" 2>/dev/null
done
codesign -f -s "$identity" --timestamp=none --generate-entitlement-der --entitlements "$work/app.entitlements" "$app" 2>/dev/null
codesign --verify --deep --strict "$app"

echo "== Export for the App Store ($destination)"
cat >"$work/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$destination</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$team</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF
rm -rf build/ios/ipa
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$work/ExportOptions.plist" \
  -exportPath build/ios/ipa "${key[@]}" >"$work/export.log" 2>&1 ||
  { grep -iE 'error' "$work/export.log" | head -5; exit 1; }

if [ "$destination" = export ]; then
  unzip -q build/ios/ipa/*.ipa -d "$work/ipa"
  aps=$(codesign -d --entitlements - --xml "$work/ipa/Payload/Runner.app" 2>/dev/null | plutil -extract aps-environment raw -)
  [ "$aps" = production ] || { echo "The build has no production push entitlement ($aps): not usable." >&2; exit 1; }
  echo "✓ $(ls build/ios/ipa/*.ipa) (signed for the App Store, push: production)"
else
  echo "✓ Uploaded: Apple processes it for 10 to 30 minutes, then it appears in TestFlight."
fi
