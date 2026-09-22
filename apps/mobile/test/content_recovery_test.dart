import 'dart:convert';
import 'dart:typed_data';

import 'package:biobalance/data/repositories/announcement_repository.dart';
import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/repositories/training_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/account_link.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/training_text.dart';
import 'package:biobalance/ui/features/training/training_editor_view_model.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class ContentServer implements HttpClientAdapter {
  final accepted = <String, Json>{};
  final requests = <Json>[];
  bool loseResponse = true;
  int version = 0;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final body = Map<String, dynamic>.from(options.data);
    requests.add(body);
    final key = '${body['submissionId'] ?? body['id']}';
    final result = accepted.putIfAbsent(
      key,
      () => {
        'id': body['id'],
        'version': ++version,
        'recipients': 1,
        'authorId': 'account',
        'updatedAt': '2026-01-01T00:00:00Z',
        ...body,
      },
    );
    if (loseResponse) {
      loseResponse = false;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      );
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

class SwitchingDraftRepository extends OfflineRepository {
  SwitchingDraftRepository(super.db, super.api);
  @override
  Future<void> saveDraft(
    String accountId,
    String storeId,
    String key,
    Json value,
  ) async {
    await super.saveDraft(accountId, storeId, key, value);
    api.authenticate('other', accountId: 'other');
  }
}

void main() {
  late AppDatabase db;
  late ApiClient api;
  late OfflineRepository local;
  late ContentServer server;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    server = ContentServer();
    api = ApiClient(
      baseUrl: 'http://test',
      dio: Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = server,
    )..authenticate('token', accountId: 'account');
    local = OfflineRepository(db, api);
  });
  tearDown(() async => db.close());
  final article = <String, dynamic>{
    'id': 'content',
    'expectedVersion': 0,
    'title': 'Conseils PDRN',
    'body': 'Bonjour',
    'type': 'article',
    'mediaId': null,
    'status': 'draft',
    'productIds': ['p'],
  };
  test('training retries a lost response with the original submission, then applies later local edits to its accepted version', () async {
    final repository = TrainingRepository(local, api);
    await expectLater(
      repository.save('account', article),
      throwsA(isA<DioException>()),
    );
    final recovered = await TrainingRepository(
      local,
      api,
    ).save('account', {...article, 'title': 'Conseils modifiés'});
    expect(server.accepted, hasLength(2));
    expect(server.requests[0], server.requests[1]);
    expect(server.requests[2]['expectedVersion'], 1);
    expect(recovered['version'], 2);
    expect(
      (await local.draft('account', '', 'training-submit:content'))?.isEmpty,
      true,
    );
  });
  test(
    'announcement retry is immutable and cannot be sent under another account',
    () async {
      final repository = AnnouncementRepository(local, api);
      final store = Store.fromJson({
        'id': 'store',
        'organizationId': 'org',
        'name': 'Tunis',
        'permissions': ['manage'],
      });
      final message = <String, dynamic>{
        'id': 'message',
        'title': 'Formation',
        'body': 'Nouvelle formation',
        'audience': 'salespeople',
      };
      await expectLater(
        repository.send('account', store, message),
        throwsA(isA<DioException>()),
      );
      await expectLater(
        repository.send('account', store, {...message, 'body': 'Changed'}),
        throwsA(isA<AppFailure>()),
      );
      expect(server.requests, hasLength(1));
      await repository.send('account', store, message);
      expect(server.accepted, hasLength(1));
      expect(server.requests[0], server.requests[1]);
      api.authenticate('other', accountId: 'other');
      await expectLater(
        repository.send('account', store, message),
        throwsA(isA<AppFailure>()),
      );
      expect(server.requests, hasLength(2));
    },
  );
  test('account changes during local persistence cannot send a draft under the new identity', () async {
    final switching = SwitchingDraftRepository(db, api);
    await expectLater(
      TrainingRepository(switching, api).save('account', article),
      throwsA(isA<AppFailure>()),
    );
    expect(server.requests, isEmpty);
    api.authenticate('token', accountId: 'account');
    final store = Store.fromJson({
      'id': 'store',
      'organizationId': 'org',
      'name': 'Tunis',
      'permissions': ['manage'],
    });
    await expectLater(
      AnnouncementRepository(switching, api).send('account', store, {
        'id': 'message',
        'title': 'Titre',
        'body': 'Corps',
        'audience': 'all',
      }),
      throwsA(isA<AppFailure>()),
    );
    expect(server.requests, isEmpty);
  });
  test('new training drafts preserve identity, product associations and upload source across editor disposal', () async {
    const user = UserAccount(
      id: 'account',
      name: 'Admin',
      email: 'admin@example.test',
      admin: true,
    );
    final workspace = WorkspaceViewModel(user, local, api);
    final first = TrainingEditorViewModel(workspace, null);
    await first.restore();
    final id = first.state.value('id');
    first.change({
      'title': 'Formation PDRN',
      'productIds': '["p"]',
      'filePath': '/tmp/video.mp4',
      'fileName': 'video.mp4',
    });
    await first.draft.flush();
    first.dispose();
    final second = TrainingEditorViewModel(workspace, null);
    await second.restore();
    expect(second.state.value('id'), id);
    expect(second.productIds, ['p']);
    expect(second.state.value('filePath'), '/tmp/video.mp4');
    expect(second.preview()['title'], 'Formation PDRN');
    second.dispose();
    workspace.dispose();
  });
  test('account links accept activation and recovery tokens only from configured routes', () {
    final token = 'a' * 43;
    expect(
      AccountLink.parse(Uri.parse('biobalance://activate?token=$token')),
      isNull,
    );
    expect(
      AccountLink.parse(
        Uri.parse('https://app.example.test/recover?token=$token'),
        httpsHost: 'app.example.test',
      )?.mode,
      'reset',
    );
    expect(
      AccountLink.parse(
        Uri.parse('https://app.example.test/activate?token=$token'),
        httpsHost: 'app.example.test',
      )?.mode,
      'activate',
    );
    for (final link in [
      'https://evil.test/activate?token=$token',
      'biobalance://activate?token=short',
      'biobalance://activate?token=$token&token=$token',
      'biobalance://activate/other?token=$token',
      'biobalance://activate?token=$token#fragment',
    ]) {
      expect(
        AccountLink.parse(Uri.parse(link), httpsHost: 'app.example.test'),
        isNull,
      );
    }
    expect(
      TrainingText.plain(
        '<p>Conseils &amp; bénéfices</p><script>secret()</script>',
      ),
      contains('Conseils & bénéfices'),
    );
    expect(
      TrainingText.plain('<script>secret()</script>'),
      isNot(contains('secret')),
    );
  });
}
