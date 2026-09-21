import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/api/generated/models.dart';
import 'package:biobalance/domain/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('raw retries send the legacy envelope without defaults or rewriting', () async {
    const bytes =
        '{"operationId":"legacy","organizationId":"org","storeId":"store","payloadVersion":1,"command":{"type":"inventory.damage","lotId":"lot","quantity":1,"expectedVersion":2,"reason":"Dommage"}}';
    final envelope = jsonDecode(bytes) as Map<String, dynamic>;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.invalid'));
    final requests = <String>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(jsonEncode((options.data as Map)['operations'][0]));
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'results': [
                  {
                    'operationId': 'legacy',
                    'status': 'accepted',
                    'data': {'id': 'lot', 'version': 4},
                  },
                ],
              },
            ),
          );
        },
      ),
    );
    final api = ApiClient(baseUrl: 'https://example.invalid', dio: dio)
      ..authenticate('session', accountId: 'owner');
    await api.pushRaw([envelope]);
    await api.pushRaw([envelope]);
    expect(requests, [bytes, bytes]);
    dio.close();
  });
  test(
    'generated commands preserve optional field presence and exact millimes',
    () {
      final source = <String, dynamic>{
        'operationId': 'op',
        'organizationId': 'org',
        'storeId': 'store',
        'payloadVersion': 1,
        'command': {
          'type': 'sale.create',
          'saleId': 'sale',
          'occurredAt': '2026-09-21T10:00:00Z',
          'lines': [
            {
              'id': 'line',
              'productId': 'product',
              'quantity': 1,
              'unitPriceMillimes': '999999999999999',
              'allocations': [
                {'lotId': 'lot', 'quantity': 1},
              ],
            },
          ],
        },
      };
      final operation = SyncOperationDto.fromJson(source);
      expect(operation.command, isA<CommandSaleCreateDto>());
      expect(operation.toJson(), source);
      expect(operation.payloadVersion, isA<int>());
      expect(operation.toJson().containsKey('dependencies'), isFalse);
      final money = MoneyDto.fromJson({
        'currency': 'TND',
        'millimes': '999999999999999',
      });
      expect(Money(int.parse(money.millimes)).millimes, 999999999999999);
    },
  );
  test(
    'explicit null image removal remains distinct from an omitted change',
    () {
      final source = <String, dynamic>{
        'name': 'Magasin',
        'address': 'Rue de Tunis',
        'city': 'Tunis',
        'expectedVersion': 1,
        'imageId': null,
      };
      final update = WorkspaceUpdateStoreRequestDto.fromJson(source);
      expect(update.toJson(), source);
      expect(update.toJson().containsKey('phone'), isFalse);
      expect(update.toJson().containsKey('imageId'), isTrue);
    },
  );
  test(
    'result and page unions decode all statuses and reject ambiguous data',
    () {
      expect(
        SyncResultDto.fromJson({
          'operationId': 'op',
          'status': 'accepted',
          'data': {'id': 'sale', 'version': 1},
          'committedCursor': '9007199254740993',
          'affectedVersions': [],
        }),
        isA<SyncResultAcceptedDto>(),
      );
      expect(
        OperationStatusDto.fromJson({'operationId': 'op', 'status': 'unknown'}),
        isA<OperationStatusUnknownDto>(),
      );
      for (final status in ['conflict', 'rejected', 'blocked', 'retryable']) {
        final result = SyncResultDto.fromJson({
          'operationId': 'op',
          'status': status,
          'code': 'TEST',
          'message': 'Message',
        });
        expect((result.toJson() as Map)['status'], status);
      }
      expect(
        () =>
            SyncResultDto.fromJson({'operationId': 'op', 'status': 'accepted'}),
        throwsFormatException,
      );
      expect(
        SnapshotPageDto.fromJson({
          'resource': 'lots',
          'items': [],
          'nextPage': null,
          'cursor': '1',
        }),
        isA<SnapshotPageLotsDto>(),
      );
    },
  );
}
