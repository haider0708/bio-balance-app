import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'repository_context.dart';
import 'offline_repository.dart';
import 'media_download_repository.dart';

/// Account-bound, verified image cache. Three transfers at most; disk eviction
/// affects disposable photographs only, never downloaded training or drafts.
class PhotoRepository {
  final RepositoryContext context;
  final OfflineRepository local;
  final String account;
  final _pending = <String, Future<File>>{};
  final _waiting = Queue<Completer<void>>();
  final _cancel = CancelToken();
  int _active = 0;
  bool _closed = false;
  PhotoRepository(this.context, this.local, this.account);
  Future<Directory> directory() async {
    final root = await getApplicationSupportDirectory();
    return Directory('${root.path}/photos').create(recursive: true);
  }

  Future<File> get(String id, {bool thumbnail = true}) {
    final key = '$id:$thumbnail';
    return _pending.putIfAbsent(
      key,
      () => _load(id, thumbnail).whenComplete(() {
        _pending.remove(key);
      }),
    );
  }

  Future<File> _load(String id, bool thumbnail) async {
    context.check();
    if (_closed) throw StateError('Photo cache closed');
    final downloader = MediaDownloadRepository(
      local,
      context.api,
      directory: directory,
      thumbnail: thumbnail,
      maxBytes: thumbnail ? 1024 * 1024 : 16 * 1024 * 1024,
    );
    final cached = await downloader.cached(account, id);
    if (cached != null) {
      context.check();
      return cached;
    }
    if (_active >= 3) {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    } else {
      _active++;
    }
    try {
      if (_closed) throw StateError('Photo cache closed');
      final file = await downloader.download(account, id, _cancel, (_) {});
      context.check();
      await _trim(file);
      return file;
    } finally {
      if (_waiting.isNotEmpty) {
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }

  Future<void> _trim(File keep) async {
    final files = <({File file, int bytes, DateTime modified})>[];
    await for (final entry in (await directory()).list()) {
      if (entry is! File) continue;
      final stat = await entry.stat();
      if (entry.path.endsWith('.part')) {
        if (DateTime.now().difference(stat.modified).inDays >= 1) {
          await entry.delete().catchError((Object _) => entry);
        }
        continue;
      }
      files.add((file: entry, bytes: stat.size, modified: stat.modified));
    }
    var bytes = files.fold<int>(0, (sum, e) => sum + e.bytes);
    files.sort((a, b) => a.modified.compareTo(b.modified));
    for (final entry in files) {
      if (bytes <= 64 * 1024 * 1024) break;
      if (entry.file.path == keep.path) continue;
      try {
        await entry.file.delete();
        bytes -= entry.bytes;
      } on FileSystemException {
        /* Another completed transfer may already have evicted it. */
      }
    }
  }

  void dispose() {
    _closed = true;
    _cancel.cancel('Account workspace closed');
  }
}
