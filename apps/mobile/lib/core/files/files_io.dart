import 'dart:io';
import 'dart:typed_data';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hand a generated file (a report) to the person: the phone's share sheet.
Future<void> exportFile(
  String name,
  Uint8List bytes,
  String mime, {
  String? subject,
}) async {
  final path = await _write(name, bytes);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: mime)],
      subject: subject,
    ),
  );
}

/// Show a downloaded document (a PDF) in whatever app on the phone opens it.
Future<void> viewFile(String name, Uint8List bytes, String mime) async {
  final path = await _write(name, bytes);
  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) throw StateError('no viewer');
}

/// A URL the video player can read a downloaded video from. The phone streams from the server instead.
String? localObjectUrl(Uint8List bytes, String mime) => null;

Future<String> _write(String name, Uint8List bytes) async {
  final dir = await getTemporaryDirectory();
  final path = '${dir.path}/$name';
  await File(path).writeAsBytes(bytes, flush: true);
  return path;
}
