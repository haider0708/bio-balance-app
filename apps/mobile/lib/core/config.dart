/// Build-time settings: `--dart-define=API_BASE_URL=https://api.example.com`.
class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.galylio.com',
  );

  static const version = '2.5.0';

  /// Photos are resized on the phone before upload.
  static const photoMaxWidth = 1400.0;
  static const photoQuality = 72;
}
