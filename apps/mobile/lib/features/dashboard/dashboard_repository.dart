import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';

/// The home screen payload. Its shape depends on the role, so screens read what they need.
final dashboardProvider = FutureProvider.autoDispose.family<Json, String?>((ref, regionId) async {
  final data = await ref.watch(apiClientProvider).get('/v1/dashboard', query: {'regionId': regionId});
  return data as Json;
});
