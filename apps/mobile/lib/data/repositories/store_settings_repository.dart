import '../../domain/models/models.dart';
import '../services/api/generated/api_client.dart';

class StoreSettingsRepository {
  final ApiClient api;
  const StoreSettingsRepository(this.api);
  Future<void> update(Store store, Json values) async {
    await api.request(
      'PATCH',
      '/v1/stores/${store.id}',
      query: {'organizationId': store.organizationId},
      body: values,
    );
  }

  Future<void> onboarding(Store store, Json values) async {
    await api.request(
      'PATCH',
      '/v1/stores/${store.id}/onboarding',
      query: {'organizationId': store.organizationId},
      body: values,
    );
  }
}
