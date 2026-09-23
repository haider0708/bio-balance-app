import '../../../data/repositories/identity_repository.dart';

import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dio/dio.dart';

import '../../../data/services/notifications/push_notifications.dart';
import '../../../data/services/api/generated/api_client.dart';
import '../../../data/services/api/session_transport.dart';
import '../../../domain/models/models.dart';

enum SessionStatus {
  signedOut,
  authenticated,
  offline,
  expired,
  disabled,
  storeAccessRevoked,
}

class SessionState {
  final UserAccount? user;
  final bool restoring, busy;
  final String? error;
  final SessionStatus status;
  const SessionState({
    this.user,
    this.restoring = false,
    this.busy = false,
    this.error,
    this.status = SessionStatus.signedOut,
  });
}

class SessionViewModel extends ChangeNotifier {
  late final identity = IdentityRepository(api);

  final ApiClient api;
  final PushNotifications? notifications;
  final FlutterSecureStorage secureStorage;
  final Future<void> Function()? prepareStorage;
  final _exitGuards = <Future<void> Function()>{};
  late final StreamSubscription<AccessEvent> _events;
  bool _closed = false;
  int _action = 0;
  Future<bool>? _loggingOut;
  Future<void> _storageTail = Future.value();
  Future<void> _store(Future<void> Function() action) {
    final next = _storageTail.then((_) => action());
    _storageTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> flushAccessState() => _storageTail;

  SessionState state = const SessionState(restoring: true);
  SessionViewModel(
    this.api,
    this.secureStorage, {
    this.notifications,
    this.prepareStorage,
  }) {
    _events = api.accessEvents.listen((event) {
      if (event.binding.generation != api.generation ||
          state.user?.id != event.binding.accountId) {
        return;
      }
      final status = switch (event.condition) {
        AccessCondition.authenticated => SessionStatus.authenticated,
        AccessCondition.offline => SessionStatus.offline,
        AccessCondition.expired => SessionStatus.expired,
        AccessCondition.disabled => SessionStatus.disabled,
        AccessCondition.storeAccessRevoked ||
        AccessCondition.groupAccessRevoked => SessionStatus.storeAccessRevoked,
      };
      // A response started before confirmed expiry cannot restore a session.
      if ([
            SessionStatus.expired,
            SessionStatus.disabled,
          ].contains(state.status) &&
          status == SessionStatus.authenticated) {
        return;
      }
      if (status == SessionStatus.expired || status == SessionStatus.disabled) {
        final token = event.binding.authorization?.replaceFirst('Bearer ', '');
        unawaited(
          _store(() async {
            final value = await secureStorage.read(key: 'session');
            if (value == null) return;
            final saved = Map<String, dynamic>.from(jsonDecode(value));
            // A queued denial must never overwrite a later successful login.
            if (saved['token'] != token ||
                saved['user']['id'] != event.binding.accountId) {
              return;
            }
            saved['accessDenied'] = status.name;
            await secureStorage.write(key: 'session', value: jsonEncode(saved));
          }).catchError((Object _) {
            if (!_closed && api.generation == event.binding.generation) {
              _emit(
                SessionState(
                  user: state.user,
                  status: status,
                  error: 'Impossible de conserver l’état d’accès. Reconnectez-vous avant de continuer.',
                ),
              );
            }
          }),
        );
      }
      _emit(SessionState(user: state.user, status: status));
    });
  }
  VoidCallback registerExitGuard(Future<void> Function() guard) {
    _exitGuards.add(guard);
    return () => _exitGuards.remove(guard);
  }

  void _emit(SessionState value) {
    if (_closed) return;
    state = value;
    notifyListeners();
  }

  Future<void> restore() async {
    final action = ++_action;
    try {
      await prepareStorage?.call();
      final value = await secureStorage.read(key: 'session');
      if (action != _action || _closed) return;
      if (value == null) {
        _emit(const SessionState());
        return;
      }
      final saved = Map<String, dynamic>.from(jsonDecode(value));
      api.authenticate(saved['token'], accountId: saved['user']['id']);
      final expiry = DateTime.tryParse('${saved['expiresAt']}');
      final disabled = saved['accessDenied'] == 'disabled';
      final expired =
          disabled ||
          saved['accessDenied'] == 'expired' ||
          (expiry != null && !expiry.isAfter(DateTime.now()));
      if (expired) api.markExpired();
      _emit(
        SessionState(
          user: UserAccount.fromJson(saved['user']),
          status: disabled
              ? SessionStatus.disabled
              : expired
              ? SessionStatus.expired
              : SessionStatus.offline,
        ),
      );
      if (!expired) unawaited(notifications?.resume());
    } catch (_) {
      if (action == _action) {
        _emit(
          const SessionState(
            error: 'Le stockage sécurisé est indisponible. Veuillez vous reconnecter.',
          ),
        );
      }
    }
  }

  Future<bool> login(String email, String password, String otp) async {
    final action = ++_action;
    _emit(SessionState(user: state.user, status: state.status, busy: true));
    try {
      final result = await identity.login(email, password, otp);
      if (action != _action || _closed) return false;
      final user = UserAccount.fromJson(result['user']);
      await _store(
        () => secureStorage.write(key: 'session', value: jsonEncode(result)),
      );
      if (action != _action || _closed) return false;
      api.authenticate(result['token'], accountId: user.id);
      _emit(SessionState(user: user, status: SessionStatus.authenticated));
      unawaited(notifications?.resume());
      return true;
    } catch (e) {
      if (action == _action) {
        _emit(
          SessionState(
            user: state.user,
            status: state.status,
            error: message(e),
          ),
        );
      }
      return false;
    }
  }

  Future<bool> logout() => _loggingOut ??= _logout().whenComplete(() {
    _loggingOut = null;
  });

  Future<bool> _logout() async {
    final action = ++_action;
    final previous = api.binding;
    try {
      await Future.wait(_exitGuards.toList().map((save) => save()));
      if (action != _action || _closed) return false;
      await _store(() async {
        if (action == _action && !_closed) {
          await secureStorage.delete(key: 'session');
        }
      });
      if (action != _action || _closed) return false;
      api.authenticate(null);
      _emit(const SessionState());
      // Cleanup uses the old binding; network failure cannot block local logout.
      unawaited(api.revoke(previous).catchError((Object _) {}));
      unawaited(notifications?.unbind().catchError((Object _) {}));
      return true;
    } catch (e) {
      if (action == _action && !_closed) {
        _emit(
          SessionState(
            user: state.user,
            status: state.status,
            error:
                'Déconnexion interrompue. Vos brouillons restent ouverts. '
                'Vérifiez le stockage du téléphone, puis réessayez.',
          ),
        );
      }
      return false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _action++;
    unawaited(_events.cancel());
    _exitGuards.clear();
    super.dispose();
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
