/// A failed request, with a stable [code] the app translates for the user.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.status,
    this.fields = const {},
    this.details,
  });

  final String code;
  final String message;
  final int? status;

  /// Per-field messages for validation errors, keyed by field path.
  final Map<String, String> fields;
  final Object? details;

  bool get isOffline => code == 'OFFLINE';
  bool get isUnauthorized => status == 401;
  bool get isConflict => status == 409;

  @override
  String toString() => 'ApiException($code, $status)';
}
