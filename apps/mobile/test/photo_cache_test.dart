import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:biobalance/data/repositories/photo_repository.dart';
import 'package:biobalance/data/repositories/repository_context.dart';
import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class PhotoServer implements HttpClientAdapter {
  final bytes = Uint8List.fromList(List.generate(100, (i) => i));
  bool fail = false;
  int downloads = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    if (options.path.endsWith('/metadata')) {
      expect(options.queryParameters['variant'], 'thumbnail');
      return ResponseBody.fromString(
        jsonEncode({
          'id': 'photo',
          'mime': 'image/png',
          'size': '${bytes.length}',
          'sha256': sha256.convert(bytes).toString(),
        }),
        200,
        headers: {
          Headers.contentTypeHeader: ['application/json'],
        },
      );
    }
    downloads++;
    if (fail) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
    }
    return ResponseBody(
      Stream.value(bytes),
      200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class LocalPhotos extends PhotoRepository {
  final Directory root;
  LocalPhotos(super.context, super.local, super.account, this.root);
  @override
  Future<Directory> directory() async => root;
}

void main() {
  late Directory directory;
  late AppDatabase db;
  late ApiClient api;
  late LocalPhotos photos;
  late PhotoServer server;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('biobalance-photo-');
    db = AppDatabase(NativeDatabase.memory());
    server = PhotoServer();
    api = ApiClient(
      baseUrl: 'http://test',
      dio: Dio()..httpClientAdapter = server,
    )..authenticate('test', accountId: 'account');
    photos = LocalPhotos(
      RepositoryContext(api),
      OfflineRepository(db, api),
      'account',
      directory,
    );
  });
  tearDown(() async {
    photos.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });
  test('a downloaded photograph completes, shares its pending transfer and works offline', () async {
    final first = photos.get('photo');
    expect(identical(first, photos.get('photo')), isTrue);
    final file = await first.timeout(const Duration(seconds: 3));
    expect(await file.readAsBytes(), server.bytes);
    server.fail = true;
    expect(
      (await photos.get('photo').timeout(const Duration(seconds: 3))).path,
      file.path,
    );
    expect(server.downloads, 1);
  });
  test(
    'a failed photograph completes with its error and can be retried',
    () async {
      server.fail = true;
      await expectLater(
        photos.get('photo').timeout(const Duration(seconds: 3)),
        throwsA(isA<DioException>()),
      );
      server.fail = false;
      expect(
        await (await photos.get('photo').timeout(const Duration(seconds: 3)))
            .readAsBytes(),
        server.bytes,
      );
      expect(server.downloads, 2);
    },
  );
}
