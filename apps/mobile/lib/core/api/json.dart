typedef Json = Map<String, dynamic>;

/// Small, forgiving readers for server JSON. A missing or null field never crashes a screen.
extension JsonReader on Json {
  String str(String key, [String fallback = '']) => (this[key] as String?) ?? fallback;
  String? strOrNull(String key) => this[key] as String?;
  int integer(String key, [int fallback = 0]) => (this[key] as num?)?.toInt() ?? fallback;
  int? integerOrNull(String key) => (this[key] as num?)?.toInt();
  bool flag(String key, [bool fallback = false]) => (this[key] as bool?) ?? fallback;

  DateTime? dateOrNull(String key) {
    final raw = this[key] as String?;
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  DateTime date(String key) => dateOrNull(key) ?? DateTime.fromMillisecondsSinceEpoch(0);

  Json obj(String key) => (this[key] as Map<String, dynamic>?) ?? const {};
  Json? objOrNull(String key) => this[key] as Map<String, dynamic>?;

  List<Json> list(String key) =>
      ((this[key] as List<dynamic>?) ?? const []).cast<Json>();
}

List<Json> jsonList(Object? value) => ((value as List<dynamic>?) ?? const []).cast<Json>();
