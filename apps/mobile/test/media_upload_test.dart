import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:biobalance/data/repositories/media_upload_repository.dart';
import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class UploadServer implements HttpClientAdapter {
  final assets = <String, Json>{};
  int writes = 0;
  bool loseFinal = true;
  Json? lastStart;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Json result;
    if (options.method == 'POST') {
      lastStart = Map<String, dynamic>.from(options.data);
      final id = 'asset-${assets.length}';
      result = {
        'id': id,
        'size': options.data['size'],
        'expectedSha256': options.data['sha256'],
        'status': 'uploading',
        'received': 0,
      };
      assets[id] = result;
    } else {
      final id = options.path.split('/').last;
      result = assets[id]!;
      if (options.method == 'PUT') {
        writes++;
        result['received'] = result['size'];
        result['status'] = 'processing';
        if (loseFinal) {
          loseFinal = false;
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.receiveTimeout,
          );
        }
      }
    }
    return ResponseBody.fromString(
      jsonEncode(result),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('image upload recovers lost final response and never resumes a different same-size file', () async {
    final dir = await Directory.systemTemp.createTemp('biobalance-upload-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/image.jpg');
    await file.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3, 4]);
    final server = UploadServer(),
        api = ApiClient(
          baseUrl: 'http://test',
          dio: Dio(BaseOptions(baseUrl: 'http://test'))
            ..httpClientAdapter = UploadServer(),
        );
    api.http.httpClientAdapter = server;
    api.authenticate('token', accountId: 'a');
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = MediaUploadRepository(OfflineRepository(db, api), api);
    final store = Store.fromJson({
      'id': 'store',
      'organizationId': 'org',
      'name': 'Test',
      'permissions': ['manage'],
    });
    Future<Json> upload() => repo.upload(
      accountId: 'a',
      file: file,
      name: 'image.jpg',
      mime: 'image/jpeg',
      purpose: 'store',
      store: store,
      cancel: CancelToken(),
      progress: (_) {},
    );
    await expectLater(upload(), throwsA(isA<DioException>()));
    expect(server.assets, hasLength(1));
    expect(server.writes, 1);
    expect(server.lastStart!['mime'], 'image/png');
    final resumed = await upload();
    expect(resumed['id'], 'asset-0');
    expect(server.writes, 1);
    await file.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10, 5, 6, 7, 8]);
    final replacement = await upload();
    expect(replacement['id'], 'asset-1');
    expect(server.assets, hasLength(2));
    api.authenticate('other', accountId: 'b');
    await expectLater(
      upload(),
      throwsA(
        isA<AppFailure>().having((e) => e.code, 'code', 'ACCOUNT_CHANGED'),
      ),
    );
    expect(server.assets, hasLength(2));
  });
}
