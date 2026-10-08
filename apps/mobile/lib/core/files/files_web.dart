import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Hand a generated file (a report) to the person: the browser saves it.
Future<void> exportFile(
  String name,
  Uint8List bytes,
  String mime, {
  String? subject,
}) async {
  final url = _url(bytes, mime);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(link);
  link.click();
  link.remove();
  _release(url);
}

/// Show a downloaded document (a PDF) in a new tab.
Future<void> viewFile(String name, Uint8List bytes, String mime) async {
  final url = _url(bytes, mime);
  web.window.open(url, '_blank');
  _release(url, after: const Duration(minutes: 2));
}

/// A URL the video player can read a downloaded video from (browsers cannot send a sign-in header with a video).
String? localObjectUrl(Uint8List bytes, String mime) => _url(bytes, mime);

String _url(Uint8List bytes, String mime) => web.URL.createObjectURL(
  web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime)),
);

void _release(String url, {Duration after = const Duration(seconds: 10)}) =>
    Future<void>.delayed(after, () => web.URL.revokeObjectURL(url));
