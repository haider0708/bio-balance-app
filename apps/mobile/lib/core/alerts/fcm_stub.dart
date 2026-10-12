import 'dart:ui' show VoidCallback;

/// A push alert that arrived while the app was open.
class FcmMessage {
  const FcmMessage(this.title, this.body);

  final String? title;
  final String? body;
}

/// No Firebase on this platform (the web console).
class Fcm {
  const Fcm._();

  static bool get supported => false;
  static Stream<FcmMessage> get foreground => const Stream.empty();
  static Future<String?> token() async => null;
  static Future<void> watchToken(void Function(String token) changed) async {}
  static Future<void> watchOpened(VoidCallback opened) async {}
}
