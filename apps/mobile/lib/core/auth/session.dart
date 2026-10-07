import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../api/json.dart';
import 'me.dart';

const _tokenKey = 'session.token';
const _meKey = 'session.me';
const _localeKey = 'app.locale';

final secureStorageProvider = Provider<FlutterSecureStorage>(
  (_) => const FlutterSecureStorage(aOptions: AndroidOptions()),
);

final preferencesProvider = FutureProvider<SharedPreferences>(
  (_) => SharedPreferences.getInstance(),
);

/// The bearer token, kept in memory so the API client can read it synchronously.
class TokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  // ignore: use_setters_to_change_properties
  void set(String? token) => state = token;
}

final tokenProvider = NotifierProvider<TokenNotifier, String?>(
  TokenNotifier.new,
);

/// The chosen language; null follows the phone.
class LocaleNotifier extends Notifier<String?> {
  @override
  String? build() {
    ref.listen(preferencesProvider, (_, next) {
      final stored = next.value?.getString(_localeKey);
      if (stored != null && state == null) state = stored;
    }, fireImmediately: true);
    return null;
  }

  Future<void> choose(String code) async {
    state = code;
    await (await ref.read(preferencesProvider.future))
        .setString(_localeKey, code);
    // Signed in: keep the account's language in step, so emails come in the language chosen here.
    if (ref.read(tokenProvider) != null) await syncAccountLanguage(ref, code);
  }
}

/// Tell the server which language this person uses (emails follow it). Never blocks the app.
Future<void> syncAccountLanguage(Ref ref, String code) async {
  try {
    await ref.read(apiClientProvider).patch('/v1/me', {'locale': code});
  } on ApiException {
    // Offline: the phone keeps the choice; the account catches up next time.
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, String?>(
  LocaleNotifier.new,
);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenReader: () => ref.read(tokenProvider),
    localeReader: () => ref.read(localeProvider) ?? 'fr',
    onUnauthorized: () => ref.read(sessionProvider.notifier).expire(),
  );
});

class Session {
  const Session({required this.token, required this.me});

  final String token;
  final Me me;
}

/// Who is signed in. Survives restarts; keeps working offline with the last known profile.
class SessionNotifier extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    final storage = ref.read(secureStorageProvider);
    final token = await storage.read(key: _tokenKey);
    if (token == null) return null;
    ref.read(tokenProvider.notifier).set(token);
    final cached = await storage.read(key: _meKey);
    try {
      final me = Me.fromJson(
        await ref.read(apiClientProvider).get('/v1/me') as Json,
      );
      await storage.write(key: _meKey, value: jsonEncode(_meJson(me)));
      return Session(token: token, me: me);
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await _clear();
        return null;
      }
      // Offline or the server is down: carry on with what we knew.
      if (cached != null) {
        return Session(
          token: token,
          me: Me.fromJson(jsonDecode(cached) as Json),
        );
      }
      rethrow;
    }
  }

  Future<void> login({
    required String email,
    required String password,
    String? otp,
  }) async {
    final response = await ref.read(apiClientProvider).post('/v1/auth/login', {
      'email': email.trim(),
      'password': password,
      if (otp != null && otp.isNotEmpty) 'otp': otp,
    }) as Json;
    final token = response.str('token');
    final me = Me.fromJson(response.obj('me'));
    final storage = ref.read(secureStorageProvider);
    await storage.write(key: _tokenKey, value: token);
    await storage.write(key: _meKey, value: jsonEncode(_meJson(me)));
    ref.read(tokenProvider.notifier).set(token);
    final chosen = ref.read(localeProvider);
    if (chosen != null && chosen != me.locale)
      unawaited(syncAccountLanguage(ref, chosen));
    state = AsyncData(Session(token: token, me: me));
  }

  Future<void> refresh() async {
    final current = state.value;
    if (current == null) return;
    final me = Me.fromJson(
      await ref.read(apiClientProvider).get('/v1/me') as Json,
    );
    await ref
        .read(secureStorageProvider)
        .write(key: _meKey, value: jsonEncode(_meJson(me)));
    state = AsyncData(Session(token: current.token, me: me));
  }

  Future<void> logout() async {
    try {
      await ref.read(apiClientProvider).post('/v1/auth/logout');
    } on ApiException {
      // Signing out always works locally, even without a connection.
    }
    await _clear();
    state = const AsyncData(null);
  }

  /// The server said the session is over.
  void expire() {
    if (state.value == null) return;
    unawaited(_clear());
    state = const AsyncData(null);
  }

  Future<void> _clear() async {
    ref.read(tokenProvider.notifier).set(null);
    final storage = ref.read(secureStorageProvider);
    await storage.delete(key: _tokenKey);
    await storage.delete(key: _meKey);
  }

  Json _meJson(Me me) => {
    'id': me.id,
    'name': me.name,
    'email': me.email,
    'phone': me.phone,
    'role': me.role.wire,
    'locale': me.locale,
    'region': me.region == null
        ? null
        : {
            'id': me.region!.id,
            'code': me.region!.code,
            'name': me.region!.name,
          },
    'pdv': me.pdv == null ? null : {'id': me.pdv!.id, 'name': me.pdv!.name},
    'depot': me.depot == null
        ? null
        : {'id': me.depot!.id, 'name': me.depot!.name},
  };
}

final sessionProvider = AsyncNotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);

/// The signed-in person. While signing out, screens that are still on display for a moment keep
/// seeing the last known person until the sign-in screen replaces them.
final meProvider = (() {
  Me? lastKnown;
  return Provider<Me>((ref) {
    final session = ref.watch(sessionProvider).value;
    if (session != null) return lastKnown = session.me;
    final previous = lastKnown;
    if (previous != null) return previous;
    throw StateError('No session');
  });
})();

/// Light, dark, or follow the phone (the default). Remembered on the phone.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    ref.listen(preferencesProvider, (_, next) {
      final stored = next.value?.getString('app.theme');
      final mode = ThemeMode.values.where((m) => m.name == stored).firstOrNull;
      if (mode != null) state = mode;
    }, fireImmediately: true);
    return ThemeMode.system;
  }

  Future<void> choose(ThemeMode mode) async {
    state = mode;
    await (await ref.read(preferencesProvider.future))
        .setString('app.theme', mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
