import '../../domain/models/models.dart';
import '../services/api/generated/api_client.dart';
import '../services/api/session_transport.dart';

/// A repository instance belongs to one authenticated workspace generation.
class RepositoryContext {
  final ApiClient api;
  final SessionBinding binding;
  RepositoryContext(this.api) : binding = api.binding;
  Future<T> run<T>(Future<T> Function() work) {
    if (api.generation != binding.generation ||
        api.accountId != binding.accountId) {
      throw const AppFailure('ACCOUNT_CHANGED', 'La session a changé.');
    }
    return work();
  }
}
