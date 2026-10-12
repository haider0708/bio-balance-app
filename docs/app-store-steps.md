# Publishing the iPhone app, step by step

For the Mac session and the owner. The texts to paste (descriptions, keywords, review notes) are in [store-publishing.md](store-publishing.md); how the app is built is in [mobile-release.md](mobile-release.md). Do the steps in order; each one says who does it.

## 0. Before anything

- **Apple Developer Program** (99 USD a year), at developer.apple.com/programs. *Owner.*
  - As a **person** (approval within hours to 2 days): the seller name shown on the App Store is the owner's own legal name.
  - As a **company** (needs a D-U-N-S number, up to 2 weeks): the company name is shown. The two cannot be switched later without a new account.
- The Team ID: developer.apple.com > Account > Membership. `scripts/mac-setup.sh` asks for it and saves it in `apps/mobile/ios/Flutter/Signing.xcconfig` (never committed).
- The Mac is prepared by `bash scripts/mac-setup.sh` (Xcode 26+, Flutter 3.47.5, CocoaPods, the checks and a first build).

## 1. Xcode signing and the push capability (Mac session, with the owner's Apple login)

1. Xcode > Settings > Accounts: sign in with the Apple ID of the developer account.
2. Open `apps/mobile/ios/Runner.xcworkspace` (the workspace, not the project). Target **Runner** > Signing & Capabilities:
   - Team: the owner's team. "Automatically manage signing" on. Bundle Identifier: `tn.biobalance.app`.
   - **Push Notifications** must be listed (the file `Runner/Runner.entitlements` already asks for it; if Xcode shows an error, add the capability with the "+" button). With automatic signing Xcode creates the App ID, the certificates and the profiles by itself.
3. Run the app once in the **iOS simulator**: `cd apps/mobile && flutter run`. Sign in with a reviewer account (in the private hand-off). Look at the opening animation, sign-in, a sale, the camera prompt (the simulator has no camera: only the prompt text), Settings.
4. Run it on a **real iPhone** (cable, "Trust this computer", Developer Mode on the phone: Settings > Privacy & Security > Developer Mode): `flutter run --release -d <the iPhone>`. Check the camera scan, the photo picker and a document picker, and that the notification permission prompt appears.

## 2. Build and upload (Mac session)

```sh
cd apps/mobile
flutter build ipa --release
```

The file is in `build/ios/ipa/`. Upload it with the **Transporter** app (drag the `.ipa`), or Xcode > Window > Organizer > Distribute App. Apple processes it for 10 to 30 minutes and emails when done. Every upload needs a build number higher than the previous one: raise the number after `+` in `pubspec.yaml` (`version: 3.3.0+40` today; the build number is the part after the `+`), commit, then build again. The number is shared with Android: it only has to keep growing.

## 3. Create the app in App Store Connect (owner, in a browser; the Mac session can read the answers out)

appstoreconnect.apple.com > My Apps > **+** > New App:
- Platform iOS. Name **BioBalance** (names are unique across the whole App Store: if it is taken, use a close variant such as "BioBalance Réseau"; the name under the icon on the phone stays "BioBalance"). Primary language **French (France)**.
- Bundle ID: `tn.biobalance.app` (it appears in the list once Xcode signing has registered it). SKU: `biobalance-ios`. User access: full.

## 4. The App Information page

- Subtitle (30 characters): FR `Ventes, stock et récompenses`; EN `Sales, stock and rewards`.
- Category: **Business** (primary). Content rights: the app shows no third-party content ("No").
- **Age rating**: answer "None" to every question, which gives **4+**.
- Privacy policy URL: `https://api.galylio.com/privacy`.
- **EU trader status (Digital Services Act)**: required for every account. As the network is a business activity, declare **trader**: the address, phone and email entered are shown on the EU product page. If the owner does not want that, remove the EU countries from availability instead.
- Availability: Tunisia (and France if wanted).

## 5. App Privacy ("nutrition label")

App Store Connect > App Privacy > Get Started. "Do you collect data?" **Yes**. Tick, for each, *linked to the user's identity*: **yes**; *used for tracking*: **no**; purpose: **App Functionality** only:

- Contact Info: Name, Email Address, Phone Number
- Identifiers: User ID, **Device ID** (the push-alert token)
- User Content: Photos or Videos, **Other User Content** (sales, stock counts, the PDF proofs)

Nothing else (no location, contacts, health, financial info, browsing, search, diagnostics, advertising data). "Tracking": **No**. These match the file `ios/Runner/PrivacyInfo.xcprivacy`; keep both in step when the data changes.

## 6. The version page (1.0 / 3.3.0)

- Screenshots: **iPhone 6.9"** from `~/.biobalance/store/iphone-6.9/fr` (1290 x 2796) and **iPad 13"** from `ipad-13/fr` (2064 x 2752); English sets in `en/`. Regenerate on the Mac if needed: `STORE_SHOTS=1 flutter test test/store_screenshots_test.dart` (they land in `build/store`).
- Promotional text, description, keywords, support URL (`https://api.galylio.com/support`), marketing URL (optional): from store-publishing.md ("Listing"). Copyright: `© 2026 <owner or company name>`.
- Build: pick the processed build. "Export compliance": already answered by the app (no special encryption). "Advertising identifier (IDFA)": **No**.
- **App Review Information**:
  - Sign-in required: **Yes**. The two reviewer accounts (team member and regional manager) are in the private hand-off. Do not give an admin account.
  - Contact: the owner's name, phone and email (Apple may call).
  - Notes: paste the "Review notes" block of store-publishing.md; it already says the app is meant for unlisted distribution.

## 7. Test with TestFlight first (owner and Mac session)

App Store Connect > TestFlight. An **internal** group (people with an App Store Connect role) needs **no Apple review**: add the owner, install the **TestFlight** app on an iPhone, accept the invitation and install the build. Check on that iPhone: sign in, a sale, the camera and photo scan, a PDF proof, account deletion, and **push** (see step 9). TestFlight and App Store builds use Apple's *production* push servers, the app already registers that way for release builds.

## 8. Submit for review, then ask for unlisted distribution

1. On the version page: **Add for Review**, then **Submit to App Review**. The first review usually takes 1 to 2 days.
2. Once it shows "Waiting for Review" or "In Review", send the **Unlisted App Distribution request** (developer.apple.com/contact/app-store, topic "Unlisted app distribution"; Apple grants it only for an app already submitted to review). Text:

```
BioBalance (tn.biobalance.app) is a business app for the partner network of [company or owner name]: parapharmacy points of sale, their regional managers and administrators, in Tunisia. Accounts are created by invitation only (an administrator or a regional manager invites each person, and the administrator approves them); there is no public sign-up, and the app has no use for anyone outside the network. We ask for Unlisted App Distribution so the app can be installed only through a link we send to the members of our network, about [number] people. The app is already submitted to review (version 3.3.0). Contact: [name, email, phone].
```

3. When Apple approves the unlisted request, the app has a **direct link** (not searchable). Send that link to the network. Those people install it like any App Store app.

## 9. Push alerts for iPhone (the Linux session does the server part)

1. developer.apple.com > Certificates, Identifiers & Profiles > **Keys** > **+** > name "BioBalance push", tick **Apple Push Notifications service (APNs)** > Continue > Register > **Download** the `.p8` (it can be downloaded once). Note the **Key ID**, and the Team ID.
2. Give the three values (`.p8` file, Key ID, Team ID) to the Linux session: it sets `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_KEY_P8` on the server (docs/runbook.md, "iPhone alerts"). Takes minutes.
3. Test on the TestFlight build: sign in as the regional manager on the iPhone, allow notifications, record a sale as the team member on another phone: the alert should arrive within seconds.

## 10. After approval, and for every update

- Release the version (manual or automatic). Watch crashes in Xcode > Organizer and TestFlight feedback.
- To update: change the code (keep it green for both platforms: [mac-handoff.md](mac-handoff.md)), raise the number after `+`, `flutter build ipa --release`, upload, add the build to a new version in App Store Connect, **What's New** text, submit. Deploy the server first if the update needs a new endpoint (the Linux session does that).

## Common refusals, and what answers them

| Apple's reason | Answer |
|---|---|
| 2.1 App completeness: could not sign in | The reviewer accounts must work during the whole review (they are in the demonstration region; do not remove it, nor change the passwords, until approved). |
| 4.2 Minimum functionality / 3.2 Unacceptable business model, "limited audience" | The app is a full business tool for a defined network; ask for **Unlisted App Distribution** (step 8). |
| 5.1.1(v) Account deletion | Settings > Delete my account (password required), and `https://api.galylio.com/account-deletion`. |
| 5.1.1 Privacy: purpose strings, data collection | Camera and photo texts are in `ios/Runner/*.lproj/InfoPlist.strings` (French and English); the privacy manifest and the App Privacy answers match (step 5). |
| 4.0 Design / crashes | Test on a real iPhone and in TestFlight before submitting; fix before the review, not after. |
