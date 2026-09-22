import 'support/test_origin.dart';

import 'dart:io';
import 'dart:convert';

import 'package:biobalance/data/repositories/media_download_repository.dart';
import 'package:biobalance/data/repositories/media_upload_repository.dart';
import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixtureFile = Platform.environment['BIOBALANCE_DEPLOYMENT_FIXTURE'];
  test(
    'Flutter resumes a real Nginx video using its opaque ETag',
    () async {
      final fixture = jsonDecode(
        await File(fixtureFile!).readAsString(),
      ) as Map<String, dynamic>;
      final folder = await Directory.systemTemp.createTemp(
        'biobalance-proxy-download-',
      );
      final context = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(fixture['certificate'] as String);
      final dio = Dio(testOptions(fixture['baseUrl'] as String))
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: () => HttpClient(context: context),
        );
      final requests = <Map<String, dynamic>>[], statuses = <int?>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (!options.path.endsWith('/metadata')) {
              requests.add(Map.of(options.headers));
            }
            handler.next(options);
          },
          onResponse: (response, handler) {
            if (!response.requestOptions.path.endsWith('/metadata')) {
              statuses.add(response.statusCode);
            }
            handler.next(response);
          },
        ),
      );
      final account = fixture['account'] as String,
          media = fixture['media'] as String;
      final api = ApiClient(baseUrl: fixture['baseUrl'] as String, dio: dio)
        ..authenticate(fixture['token'] as String, accountId: account);
      AppDatabase db = AppDatabase(
        NativeDatabase(File('${folder.path}/cache.sqlite')),
      );
      try {
        var local = OfflineRepository(db, api);
        var repository = MediaDownloadRepository(
          local,
          api,
          directory: () async => folder,
        );
        final cancel = CancelToken();
        await expectLater(
          repository.download(account, media, cancel, (value) {
            if (value > 0 && value < 1) cancel.cancel('interruption de test');
          }),
          throwsA(isA<Exception>()),
        );
        final draft = (await local.draft(account, '', 'download:$media'))!;
        expect(draft['etag'], isA<String>());
        expect(draft['etag'], isNot('"${draft['sha256']}"'));
        final partial = File(
          '${(await repository.target(account, media)).path}.part',
        );
        final offset = await partial.length();
        expect(offset, greaterThan(0));
        expect(offset, lessThan(draft['size'] as int));
        await db.close();
        db = AppDatabase(NativeDatabase(File('${folder.path}/cache.sqlite')));
        local = OfflineRepository(db, api);
        repository = MediaDownloadRepository(
          local,
          api,
          directory: () async => folder,
        );
        final file = await repository.download(
          account,
          media,
          CancelToken(),
          (_) {},
        );
        expect(requests.last['Range'], 'bytes=$offset-');
        expect(requests.last['If-Range'], draft['etag']);
        expect(statuses.last, 206);
        expect(await fileChecksum(file.path), draft['sha256']);
        expect(await repository.cached(account, media), isNotNull);
      } finally {
        await db.close();
        dio.close(force: true);
        await folder.delete(recursive: true);
      }
    },
    skip: fixtureFile == null
        ? 'Requires the isolated Compose deployment lab'
        : false,
  );
}
