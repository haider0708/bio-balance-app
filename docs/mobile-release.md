# Building and publishing the apps

Flutter 3.47.5. The server address is set at build time: `--dart-define=API_BASE_URL=https://api.galylio.com` (the default). The privacy, terms and account-deletion pages are at `https://api.galylio.com/{privacy,terms,account-deletion}` (`--dart-define=PUBLIC_SITE_URL=` to change).

```sh
cd apps/mobile
flutter pub get --enforce-lockfile
flutter analyze && flutter test
flutter build apk --debug          # a quick install on a test phone
```

The version is `version:` in `pubspec.yaml` (`3.0.0+35`): raise the number after `+` for **every** upload to either store. The app reads it from the build (Settings → About), so it can never disagree with the stores.

## Android (Google Play)

The upload key lives outside the repository, in `~/.biobalance/signing/` (`biobalance-release.jks`, `env.sh`). **Back it up**: without it the app can no longer be updated. With Play App Signing (the default) Google keeps the app signing key and this one is only the upload key — Google can reset a lost upload key, never a lost app signing key.

```sh
source ~/.biobalance/signing/env.sh
flutter build appbundle --release   # build/app/outputs/bundle/release/app-release.aab → upload this
flutter build apk --release         # a signed APK for installing by hand
```

The build refuses to produce an unsigned release. What the bundle already satisfies:

- **Target API 36** (Android 16), minimum Android 7.0 (API 24); **16 KB memory pages**: every native library is 16 KB aligned (required for new apps and updates).
- **Permissions**: internet, camera (barcodes and proof photos), notifications, and the background check for alerts. No access to photos, videos, audio or files: pictures come through the system photo picker (Play refuses broad media access for this kind of app). The background check uses a *short service* only, which needs no foreground-service declaration.
- **Icons**: adaptive icon, themed (monochrome) icon for Android 13+, a white status-bar icon for alerts.
- **Account deletion** in the app (Settings → Delete my account) and on the web (`/account-deletion`), as Play requires.
- Screenshots of the app are blocked in release builds (commercial data).

## iOS (App Store) — on the Mac

Install Xcode (latest, from the App Store) and Flutter, then:

```sh
cd apps/mobile
cp ios/Flutter/Signing.xcconfig.example ios/Flutter/Signing.xcconfig   # put your Apple Team ID in it
flutter build ipa --release        # build/ios/ipa/*.ipa
```

Upload the `.ipa` with Apple's **Transporter** app (or Xcode → Window → Organizer → Distribute App). Plugins come through Swift Package Manager: no CocoaPods needed. Bundle identifier: `tn.biobalance.app`; iOS 15 or later; iPhone and iPad.

Already in the project: the camera and photo texts in French and English, the **privacy manifest** (`PrivacyInfo.xcprivacy`: no tracking, the data collected and why), **no export-compliance question** (`ITSAppUsesNonExemptEncryption = false`, the app only uses standard HTTPS), the `biobalance://` link that opens a code from the email, portrait on iPhone and every orientation on iPad (with a side rail), and the share sheet anchored correctly on iPad.

## Store assets

Generated from the app itself, at the exact sizes each store wants, in French and English:

```sh
cd apps/mobile
STORE_SHOTS=1 flutter test test/store_screenshots_test.dart      # build/store/<device>/<fr|en>/
python3 tool/brand/make_store_graphics.py                         # feature graphic 1024×500, icon 512
```

| Store | Asset | Size | Where |
|---|---|---|---|
| App Store | iPhone 6.9" screenshots (3–10) | 1290 × 2796 | `build/store/iphone-6.9/` |
| App Store | iPad 13" screenshots (3–10) | 2064 × 2752 | `build/store/ipad-13/` |
| App Store | Icon | 1024 × 1024 | already in the build |
| Google Play | Phone screenshots (2–8) | 1080 × 2160 | `build/store/android-phone/` |
| Google Play | Tablet screenshots (optional) | 2064 × 2752 | `build/store/ipad-13/` |
| Google Play | App icon | 512 × 512 | `build/store/play-icon-512.png` |
| Google Play | Feature graphic | 1024 × 500 | `build/store/feature-graphic.png` |

The icons come from the vector leaf mark `assets/brand/leaf-mark.svg` (traced once from the logo by `tool/brand/trace_leaf.py`); `python3 tool/brand/make_icons.py` renders every launcher, store, themed, notification and web icon from it (needs pycairo).

See [store-publishing.md](store-publishing.md) for the listing texts, the privacy answers and the review notes.
