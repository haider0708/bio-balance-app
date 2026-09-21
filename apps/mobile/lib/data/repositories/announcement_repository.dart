import 'dart:convert';

import 'package:dio/dio.dart';

import '../../domain/models/models.dart';
import '../services/api/generated/api_client.dart';
import 'offline_repository.dart';

class AnnouncementRepository {
  final ApiClient api;
  final OfflineRepository local;
  AnnouncementRepository(this.local, this.api);
  Future<Json?> pending(String account, Store store) =>
      local.draft(account, store.id, 'announcement-submit');
  Future<void> send(String account, Store store, Json message) async {
    final binding = api.binding;
    if (binding.accountId != account) {
      throw const AppFailure('ACCOUNT_CHANGED', 'Reconnectez-vous.');
    }
    await local.db.transaction(() async {
      api.requireBinding(binding);
      final previous = await pending(account, store);
      if (previous?.isNotEmpty == true &&
          !['id', 'title', 'body', 'audience'].every(
            (key) => jsonEncode(previous![key]) == jsonEncode(message[key]),
          )) {
        throw const AppFailure(
          'UNCERTAIN_MESSAGE',
          'Vérifiez l’envoi précédent avant de modifier cette annonce.',
        );
      }
      await local.saveDraft(account, store.id, 'announcement-submit', message);
    });
    try {
      api.requireBinding(binding);
      await api.request(
        'POST',
        '/v1/stores/${store.id}/announcements',
        query: {'organizationId': store.organizationId},
        body: message,
      );
      await local.db.transaction(() async {
        api.requireBinding(binding);
        await local.saveDraft(account, store.id, 'announcement-submit', {});
      });
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (status == 400 || status == 422) {
        await local.saveDraft(account, store.id, 'announcement-submit', {});
      }
      rethrow;
    }
  }
}
