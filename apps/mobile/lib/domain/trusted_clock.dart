import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The time of a sale must not depend on the phone's clock. Each answer from the
/// server re-anchors this clock to the server's time; between answers it counts
/// forward from that anchor, so setting the phone's date back or turning the
/// network off cannot make a sale look older than it is.
class TrustedClock {
  static DateTime? _server, _wall;
  static final Stopwatch _monotonic = Stopwatch();
  static File? _file;

  /// Re-anchors to the server's time, as given by an HTTP `Date` header.
  static void sync(DateTime serverUtc) {
    _server = serverUtc.toUtc();
    _wall = DateTime.now().toUtc();
    _monotonic
      ..reset()
      ..start();
    _save();
  }

  /// The best known current time. The phone's clock can only move it forward:
  /// the larger of the wall-clock and monotonic elapsed time since the anchor.
  static DateTime now() {
    final server = _server, wall = _wall;
    if (server == null || wall == null) return DateTime.now().toUtc();
    final wallDelta = DateTime.now().toUtc().difference(wall);
    final elapsed = _monotonic.isRunning && _monotonic.elapsed > wallDelta
        ? _monotonic.elapsed
        : wallDelta;
    return server.add(elapsed.isNegative ? Duration.zero : elapsed);
  }

  /// Loads the last anchor after a restart, so an offline start keeps it.
  static Future<void> restore() async {
    try {
      final directory = await getApplicationSupportDirectory();
      _file = File('${directory.path}/trusted_clock.json');
      if (!await _file!.exists()) return;
      final saved = jsonDecode(await _file!.readAsString()) as Map;
      _server = DateTime.parse(saved['server'] as String).toUtc();
      _wall = DateTime.parse(saved['wall'] as String).toUtc();
    } catch (_) {
      /* No usable anchor: the phone's clock is used until the next answer. */
    }
  }

  static void _save() {
    final file = _file;
    if (file == null || _server == null) return;
    file
        .writeAsString(
          jsonEncode({
            'server': _server!.toIso8601String(),
            'wall': _wall!.toIso8601String(),
          }),
        )
        .catchError((Object _) => file);
  }

  /// For tests.
  static void reset() {
    _server = _wall = null;
    _monotonic.reset();
  }
}
