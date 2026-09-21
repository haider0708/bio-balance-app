import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:biobalance/data/repositories/media_download_repository.dart';
import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class DownloadServer implements HttpClientAdapter {
  final bytes = Uint8List.fromList(List.generate(32, (i) => i));
  bool truncate = true, corrupt = false, ignoreRange = false;
  String? etag = '"nginx-file-revision-1"';
  final requests = <RequestOptions>[];
  void Function()? duringDownload;
  String get checksum => sha256.convert(bytes).toString();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path.endsWith('/metadata')) {
      return ResponseBody.fromString(
        jsonEncode({
          'id': 'video',
          'mime': 'video/mp4',
          'size': '${bytes.length}',
          'sha256': checksum,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    requests.add(options);
    final requested = options.headers['Range'] as String?;
    final start = ignoreRange || requested == null
        ? 0
        : int.parse(requested.substring(6, requested.length - 1));
    final status = start == 0 ? 200 : 206;
    final payload = Uint8List.fromList(
      bytes.sublist(start, truncate ? 10 : bytes.length),
    );
    if (corrupt) payload[0] = 255;
    duringDownload?.call();
    return ResponseBody(
      Stream.value(payload),
      status,
      headers: {
        Headers.contentTypeHeader: ['video/mp4'],
        if (etag != null) 'etag': [etag!],
        Headers.contentLengthHeader: ['${bytes.length - start}'],
        if (status == 206)
          'content-range': ['bytes $start-${bytes.length - 1}/${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late Directory directory;
  late AppDatabase db;
  late ApiClient api;
  late OfflineRepository local;
  late DownloadServer server;
  late MediaDownloadRepository repository;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('biobalance-download-');
    db = AppDatabase(NativeDatabase.memory());
    server = DownloadServer();
    api = ApiClient(
      baseUrl: 'http://test',
      dio: Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
    )..authenticate('token', accountId: 'account');
    local = OfflineRepository(db, api);
    repository = MediaDownloadRepository(
      local,
      api,
      directory: () async => directory,
    );
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  Future<File> download() =>
      repository.download('account', 'video', CancelToken(), (_) {});

  test('a restarted downloader resumes verified partial bytes with Range and validates the completed file', () async {
    await expectLater(
      download(),
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', 'DOWNLOAD_INTERRUPTED'),
      ),
    );
    expect(await repository.cached('account', 'video'), isNull);
    repository = MediaDownloadRepository(
      local,
      api,
      directory: () async => directory,
    );
    server.truncate = false;
    final file = await download();
    expect(server.requests.last.headers['Range'], 'bytes=10-');
    expect(server.requests.last.headers['If-Range'], server.etag);
    expect(server.etag, isNot('"${server.checksum}"'));
    expect(await file.readAsBytes(), server.bytes);
    expect((await repository.cached('account', 'video'))?.path, file.path);
    final count = server.requests.length;
    await download();
    expect(server.requests.length, count);
  });
  test('a server ignoring Range restarts the partial file instead of duplicating bytes', () async {
    await expectLater(download(), throwsA(isA<AppFailure>()));
    server
      ..truncate = false
      ..ignoreRange = true;
    final file = await download();
    expect(await file.readAsBytes(), server.bytes);
  });
  test(
    'legacy partials and weak validators resume with verified ranges',
    () async {
      server.etag = 'W/"weak"';
      await expectLater(download(), throwsA(isA<AppFailure>()));
      expect(
        (await local.draft('account', '', 'download:video'))?['etag'],
        isNull,
      );
      server.truncate = false;
      final file = await download();
      expect(server.requests.last.headers['Range'], 'bytes=10-');
      expect(server.requests.last.headers.containsKey('If-Range'), isFalse);
      expect(await file.readAsBytes(), server.bytes);
    },
  );
  test('checksum failure never exposes corrupted content offline', () async {
    server
      ..truncate = false
      ..corrupt = true;
    await expectLater(
      download(),
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', 'DOWNLOAD_CHECKSUM'),
      ),
    );
    expect(await repository.cached('account', 'video'), isNull);
    expect(
      await File('${(await repository.target('account', 'video')).path}.part')
          .exists(),
      isFalse,
    );
    server.corrupt = false;
    expect(await (await download()).readAsBytes(), server.bytes);
  });
  test(
    'account switching rejects a late binary response without marking it ready',
    () async {
      server
        ..truncate = false
        ..duringDownload = () => api.authenticate('other', accountId: 'other');
      await expectLater(download(), throwsA(isA<AppFailure>()));
      expect(await repository.cached('account', 'video'), isNull);
      expect(await local.draft('other', '', 'download:video'), isNull);
    },
  );
}
