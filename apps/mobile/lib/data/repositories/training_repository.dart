import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/models.dart';
import '../services/api/generated/api_client.dart';
import 'offline_repository.dart';

class TrainingRepository {
  final ApiClient api;
  final OfflineRepository local;
  TrainingRepository(this.local, this.api);
  Future<List<Json>> cached(String account) async =>
      objects((await local.draft(account, '', 'training'))?['items']);
  Future<Json> get(String id) async =>
      Map<String, dynamic>.from(await api.request('GET', '/v1/training/$id'));
  Future<List<Json>> refresh(String account) async {
    final binding = api.binding;
    if (binding.accountId != account) {
      throw const AppFailure('ACCOUNT_CHANGED', 'Reconnectez-vous.');
    }
    final items = <Json>[];
    String? after;
    do {
      api.requireBinding(binding);
      final page = objects(
        await api.request('GET', '/v1/training', query: {'after': ?after}),
      );
      items.addAll(page);
      after = page.length == 100 ? page.last['id'] : null;
    } while (after != null);
    await local.db.transaction(() async {
      api.requireBinding(binding);
      await local.saveDraft(account, '', 'training', {'items': items});
    });
    return items;
  }

  Future<Json> save(String account, Json desired) async {
    final binding = api.binding;
    if (binding.accountId != account) {
      throw const AppFailure('ACCOUNT_CHANGED', 'Reconnectez-vous.');
    }
    final key = 'training-submit:${desired['id']}';
    final pending = await local.draft(account, '', key);
    var command = Map<String, dynamic>.from(desired);
    if (pending?['body'] is Map) {
      final previous = Map<String, dynamic>.from(pending!['body']);
      api.requireBinding(binding);
      final accepted = await _submit(account, key, previous);
      api.requireBinding(binding);
      await local.saveDraft(account, '', key, {});
      if ([
        'id',
        'title',
        'body',
        'type',
        'mediaId',
        'productIds',
        'status',
      ].every((key) => jsonEncode(previous[key]) == jsonEncode(desired[key]))) {
        return accepted;
      }
      // A later local edit is applied against the acknowledged original save.
      command['expectedVersion'] = accepted['version'];
    }
    command['submissionId'] = const Uuid().v4();
    await local.saveDraft(account, '', key, {'body': command});
    api.requireBinding(binding);
    final result = await _submit(account, key, command);
    await local.db.transaction(() async {
      api.requireBinding(binding);
      await local.saveDraft(account, '', key, {});
    });
    return result;
  }

  Future<Json> _submit(String account, String key, Json command) async {
    try {
      return Map<String, dynamic>.from(
        await api.request('POST', '/v1/training', body: command),
      );
    } on DioException catch (error) {
      if ([400, 409, 422].contains(error.response?.statusCode)) {
        await local.saveDraft(account, '', key, {});
      }
      rethrow;
    }
  }
}
