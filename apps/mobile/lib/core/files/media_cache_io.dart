import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Photos and documents kept on the phone after the first download. A stored file never
/// changes (each version has its own id), so a kept copy is always right: screens open at once
/// and mobile data is spared. The folder stays under [_limit] (the oldest files go first), is
/// excluded from backups, and is emptied when the person signs out.
class MediaCache {
  const MediaCache._();

  static const _limit = 200 * 1024 * 1024;
  static Directory? _dir;
  static int _writesSincePrune = 0;

  static Future<Directory> _folder() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/media-cache');
    await dir.create(recursive: true);
    return _dir = dir;
  }

  /// Only ids the server made (letters, digits, dashes) become file names.
  static bool _safe(String id) => RegExp(r'^[0-9a-fA-F-]{8,64}$').hasMatch(id);

  static Future<Uint8List?> read(String id) async {
    if (!_safe(id)) return null;
    try {
      final file = File('${(await _folder()).path}/$id');
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      // Touch it: recently used files are the last to be pruned.
      await file.setLastModified(DateTime.now());
      return bytes;
    } catch (_) {
      // No folder (a test, a locked phone): the file comes from the server instead.
      return null;
    }
  }

  static Future<void> write(String id, Uint8List bytes) async {
    if (!_safe(id)) return;
    try {
      final dir = await _folder();
      final temp = File('${dir.path}/$id.part');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename('${dir.path}/$id');
      if (++_writesSincePrune >= 20) {
        _writesSincePrune = 0;
        await _prune(dir);
      }
    } catch (_) {
      // A full disk only means the file is downloaded again next time.
    }
  }

  static Future<void> _prune(Directory dir) async {
    final files = <File, FileStat>{};
    await for (final entry in dir.list()) {
      if (entry is File) files[entry] = entry.statSync();
    }
    var total = files.values.fold<int>(0, (t, s) => t + s.size);
    if (total <= _limit) return;
    final oldest = files.entries.toList()
      ..sort((a, b) => a.value.modified.compareTo(b.value.modified));
    for (final e in oldest) {
      if (total <= _limit * 0.8) break;
      total -= e.value.size;
      await e.key.delete();
    }
  }

  /// Signing out leaves nothing of the account's files on the phone.
  static Future<void> clear() async {
    try {
      final dir = await _folder();
      if (dir.existsSync()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {
      // Nothing to remove.
    }
  }
}
