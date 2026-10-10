import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset, PlatformDispatcher, Rect;

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
      sharePositionOrigin: _anchor(),
    ),
  );
}

/// On an iPad the share sheet is a popover and needs a point to come from: the middle
/// of the screen (a phone ignores it).
Rect _anchor() {
  final view = PlatformDispatcher.instance.views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  return Rect.fromCenter(center: size.center(Offset.zero), width: 1, height: 1);
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
