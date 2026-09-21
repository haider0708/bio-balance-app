import 'dart:convert';
import 'dart:async';

import '../../../data/services/notifications/push_notifications.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';

import '../../../data/services/api/generated/api_client.dart';
import '../../../domain/models/models.dart';

class SessionState {
  final UserAccount? user;
  final bool restoring, busy;
  final String? error;
  const SessionState({
    this.user,
    this.restoring = false,
    this.busy = false,
    this.error,
  });
}

class SessionViewModel extends ChangeNotifier {
  final ApiClient api;
  final PushNotifications? notifications;
  final FlutterSecureStorage secureStorage;
  SessionState state = const SessionState(restoring: true);
  SessionViewModel(this.api, this.secureStorage, {this.notifications});
  Future<void> restore() async {
    try {
      final value = await secureStorage.read(key: 'session');
      if (value != null) {
        final saved = Map<String, dynamic>.from(jsonDecode(value));
        api.authenticate(saved['token'], accountId: saved['user']['id']);
        state = SessionState(user: UserAccount.fromJson(saved['user']));
        unawaited(notifications?.resume());
      } else {
        state = const SessionState();
      }
    } catch (_) {
      state = const SessionState(
        error:
            'Le stockage sécurisé est indisponible. Veuillez vous reconnecter.',
      );
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password, String otp) async {
    state = SessionState(user: state.user, busy: true);
    notifyListeners();
    try {
      final result = Map<String, dynamic>.from(
        await api.request(
          'POST',
          '/v1/identity/login',
          body: {
            'email': email.trim(),
            'password': password,
            if (otp.isNotEmpty) 'otp': otp,
          },
        ),
      );
      final user = UserAccount.fromJson(result['user']);
      await secureStorage.write(key: 'session', value: jsonEncode(result));
      api.authenticate(result['token'], accountId: user.id);
      state = SessionState(user: user);
      unawaited(notifications?.resume());
      notifyListeners();
      return true;
    } catch (e) {
      state = SessionState(error: message(e));
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await notifications?.unbind();
    try {
      await api.request('POST', '/v1/identity/logout');
    } catch (_) {}
    await secureStorage.delete(key: 'session');
    api.authenticate(null);
    state = const SessionState();
    notifyListeners();
  }

  static String message(Object error) {
    if (error is AppFailure) return error.message;
    if (error is FormatException) return error.message;
    if (error is DioException) {
      final body = error.response?.data;
      if (body is Map && body['message'] is String) return body['message'];
      return 'Connexion indisponible. Vos données et brouillons sont conservés.';
    }
    return 'L’opération n’a pas pu être terminée. Réessayez.';
  }
}
