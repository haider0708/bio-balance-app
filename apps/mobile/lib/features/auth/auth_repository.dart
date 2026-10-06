import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session.dart';

class AuthRepository {
  AuthRepository(this._ref);

  final Ref _ref;

  Future<void> activate({required String email, required String code, required String password, String? name}) =>
      _ref.read(apiClientProvider).post('/v1/auth/activate', {
        'email': email.trim(),
        'code': code.trim(),
        'password': password,
        if (name != null && name.trim().length >= 2) 'name': name.trim(),
      });

  Future<void> forgot(String email) =>
      _ref.read(apiClientProvider).post('/v1/auth/forgot-password', {'email': email.trim()});

  Future<void> reset({required String email, required String code, required String password}) =>
      _ref.read(apiClientProvider).post('/v1/auth/reset-password', {
        'email': email.trim(),
        'code': code.trim(),
        'password': password,
      });

  Future<void> changePassword({required String current, required String next}) =>
      _ref.read(apiClientProvider).post('/v1/me/password', {'current': current, 'next': next});

  Future<void> updateProfile({String? name, String? phone, String? locale}) =>
      _ref.read(apiClientProvider).patch('/v1/me', {
        'name': ?name,
        if (phone != null) 'phone': phone.isEmpty ? null : phone,
        'locale': ?locale,
      });
}

final authRepositoryProvider = Provider<AuthRepository>(AuthRepository.new);
