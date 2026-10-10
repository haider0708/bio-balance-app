import 'dart:typed_data';

/// In a browser the files are not kept on disk by the app.
class MediaCache {
  const MediaCache._();

  static Future<Uint8List?> read(String id) async => null;
  static Future<void> write(String id, Uint8List bytes) async {}
  static Future<void> clear() async {}
}
