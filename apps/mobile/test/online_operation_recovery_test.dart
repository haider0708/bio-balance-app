import 'dart:convert';

import 'package:biobalance/data/repositories/offline_repository.dart';
import 'package:biobalance/data/repositories/online_operations_repository.dart';
import 'package:biobalance/data/repositories/repository_context.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a lost online response settles the original payload before accepting changed input', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    final sent = <String>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final op = (options.data as Map)['operations'][0] as Json;
          sent.add(jsonEncode(op));
          if (sent.length == 1) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.receiveTimeout,
              ),
            );
          } else {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'results': [
                    {
                      'operationId': op['operationId'],
                      'status': 'accepted',
                      'data': {'id': 'order'},
                    },
                  ],
                },
              ),
            );
          }
        },
      ),
    );
    final api = ApiClient(baseUrl: 'https://example.invalid', dio: dio)
      ..authenticate('test-only', accountId: 'owner');
    final db = AppDatabase(NativeDatabase.memory());
    final local = OfflineRepository(db, api);
    const user = UserAccount(
      id: 'owner',
      email: 'owner@example.test',
      name: 'Test',
      admin: true,
    );
    final store = Store.fromJson({
      'id': 'store',
      'organizationId': 'org',
      'name': 'Magasin',
      'permissions': ['manage'],
    });
    final repo = OnlineOperationsRepository(
      RepositoryContext(api),
      local,
      user,
    );
    final first = <String, dynamic>{
      'type': 'order.amend',
      'orderId': 'order',
      'reason': 'Quantité réelle',
      'lines': [
        {'productId': 'p', 'quantity': 5},
      ],
    };
    await expectLater(
      repo.submit(store, first, expectedVersion: 2),
      throwsA(anything),
    );
    final changed = {
      ...first,
      'lines': [
        {'productId': 'p', 'quantity': 8},
      ],
    };
    await expectLater(
      repo.submit(store, changed, expectedVersion: 2),
      throwsA(
        isA<AppFailure>().having(
          (e) => e.code,
          'code',
          'PREVIOUS_COMMAND_CONFIRMED',
        ),
      ),
    );
    expect(sent[1], sent[0]);
    expect(
      await local.draft(user.id, store.id, 'online:order.amend:order'),
      isEmpty,
    );
    await repo.submit(store, changed, expectedVersion: 3);
    expect(jsonDecode(sent[2])['command'], changed);
    expect(
      jsonDecode(sent[2])['operationId'],
      isNot(jsonDecode(sent[0])['operationId']),
    );
    dio.close();
    await db.close();
  });
}
