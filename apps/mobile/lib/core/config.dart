/// Build-time settings: `--dart-define=API_BASE_URL=https://api.example.com`.
class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.galylio.com',
  );

  /// Where the privacy policy, the terms and the account-deletion page live.
  static const publicSiteUrl = String.fromEnvironment(
    'PUBLIC_SITE_URL',
    defaultValue: 'https://api.galylio.com',
  );

  /// Photos are resized on the phone before upload.
  static const photoMaxWidth = 1400.0;
  static const photoQuality = 72;
}
