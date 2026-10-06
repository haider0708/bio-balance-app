# Building the apps

Flutter 3.47.5. The server address is set at build time: `--dart-define=API_BASE_URL=https://api.galylio.com` (the default).

```sh
cd apps/mobile
flutter pub get --enforce-lockfile
flutter analyze && flutter test
flutter build apk --debug          # for a quick install on a test phone
```

## Signed Android release

Create the upload key once and keep it **outside the repository** (and backed up: losing it means new installs cannot update the old app).

```sh
export BIOBALANCE_KEYSTORE=/secure/path/biobalance.jks
export BIOBALANCE_KEYSTORE_PASSWORD=… BIOBALANCE_KEY_ALIAS=biobalance BIOBALANCE_KEY_PASSWORD=…
flutter build apk --release        # or: flutter build appbundle --release for Google Play
```

The build refuses to produce a release without the keystore variables. Bump `version:` in `pubspec.yaml` (`2.0.0+30`: the number after `+` must increase with every upload).

## iOS

Open `ios/Runner.xcworkspace` on a Mac with the Apple team, set the signing team, then `flutter build ipa`. Camera and photo-library texts are already in `Info.plist` in both languages.

## Branding

`python3 scripts/generate-brand-assets.py` regenerates the launcher icons and splash screens from `apps/mobile/assets/brand/biobalance-logo.jpg` (needs Pillow).
