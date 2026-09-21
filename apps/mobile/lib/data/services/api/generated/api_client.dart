// GENERATED from contracts/openapi/biobalance.json. Do not edit.
import '../session_transport.dart';

class ApiClient extends SessionTransport {
  ApiClient({required super.baseUrl, super.dio});
  Future<Map<String, dynamic>> push(
    List<Map<String, dynamic>> operations,
  ) async => Map<String, dynamic>.from(
    await request('POST', '/v1/sync/push', body: {'operations': operations}),
  );
  Future<Map<String, dynamic>> snapshot(
    String storeId,
    String organizationId,
  ) async => Map<String, dynamic>.from(
    await request(
      'GET',
      '/v1/stores/$storeId/snapshot',
      query: {'organizationId': organizationId},
    ),
  );
  Future<dynamic> adminControllerOverview({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('GET', '/v1/admin/overview', query: query, body: body);
  Future<dynamic> healthControllerHealth({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('GET', '/health', query: query, body: body);
  Future<dynamic> identityControllerLogin({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/identity/login', query: query, body: body);
  Future<dynamic> identityControllerMe({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('GET', '/v1/identity/me', query: query, body: body);
  Future<dynamic> identityControllerLogout({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/identity/logout', query: query, body: body);
  Future<dynamic> identityControllerInvite({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/identity/invitations', query: query, body: body);
  Future<dynamic> identityControllerActivate({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/identity/activate', query: query, body: body);
  Future<dynamic> identityControllerForgot({
    Map<String, dynamic>? query,
    dynamic body,
  }) =>
      request('POST', '/v1/identity/forgot-password', query: query, body: body);
  Future<dynamic> identityControllerReset({
    Map<String, dynamic>? query,
    dynamic body,
  }) =>
      request('POST', '/v1/identity/reset-password', query: query, body: body);
  Future<dynamic> workspaceControllerOrganizations({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('GET', '/v1/organizations', query: query, body: body);
  Future<dynamic> workspaceControllerStores({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('GET', '/v1/stores', query: query, body: body);
  Future<dynamic> workspaceControllerCreate({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/stores', query: query, body: body);
  Future<dynamic> workspaceControllerSnapshot({
    required String store,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'GET',
    '/v1/stores/${Uri.encodeComponent(store)}/snapshot',
    query: query,
    body: body,
  );
  Future<dynamic> workspaceControllerSnapshotPage({
    required String store,
    required String page,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'GET',
    '/v1/stores/${Uri.encodeComponent(store)}/snapshot-pages/${Uri.encodeComponent(page)}',
    query: query,
    body: body,
  );
  Future<dynamic> workspaceControllerCollection({
    required String store,
    required String resource,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'GET',
    '/v1/stores/${Uri.encodeComponent(store)}/collections/${Uri.encodeComponent(resource)}',
    query: query,
    body: body,
  );
  Future<dynamic> workspaceControllerHistory({
    required String store,
    required String resource,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'GET',
    '/v1/stores/${Uri.encodeComponent(store)}/history/${Uri.encodeComponent(resource)}',
    query: query,
    body: body,
  );
  Future<dynamic> workspaceControllerSale({
    required String store,
    required String sale,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'GET',
    '/v1/stores/${Uri.encodeComponent(store)}/sales/${Uri.encodeComponent(sale)}',
    query: query,
    body: body,
  );
  Future<dynamic> workspaceControllerChanges({
    required String store,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'GET',
    '/v1/stores/${Uri.encodeComponent(store)}/changes',
    query: query,
    body: body,
  );
  Future<dynamic> workspaceControllerRanking({
    required String store,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'GET',
    '/v1/stores/${Uri.encodeComponent(store)}/ranking',
    query: query,
    body: body,
  );
  Future<dynamic> workspaceControllerConfig({
    required String store,
    required String product,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'PATCH',
    '/v1/stores/${Uri.encodeComponent(store)}/products/${Uri.encodeComponent(product)}',
    query: query,
    body: body,
  );
  Future<dynamic> workspaceControllerMember({
    required String store,
    required String user,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'PATCH',
    '/v1/stores/${Uri.encodeComponent(store)}/team/${Uri.encodeComponent(user)}',
    query: query,
    body: body,
  );
  Future<dynamic> workspaceControllerOnboarding({
    required String store,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'PATCH',
    '/v1/stores/${Uri.encodeComponent(store)}/onboarding',
    query: query,
    body: body,
  );
  Future<dynamic> workspaceControllerReward({
    required String store,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'POST',
    '/v1/stores/${Uri.encodeComponent(store)}/rewards',
    query: query,
    body: body,
  );
  Future<dynamic> catalogControllerSave({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/catalog/products', query: query, body: body);
  Future<dynamic> catalogControllerImport({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/catalog/import', query: query, body: body);
  Future<dynamic> operationsControllerStatus({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/sync/status', query: query, body: body);
  Future<dynamic> operationsControllerPush({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/sync/push', query: query, body: body);
  Future<dynamic> notificationsControllerList({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('GET', '/v1/notifications', query: query, body: body);
  Future<dynamic> notificationsControllerRead({
    required String id,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'PATCH',
    '/v1/notifications/${Uri.encodeComponent(id)}/read',
    query: query,
    body: body,
  );
  Future<dynamic> notificationsControllerRemoveDevice({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('DELETE', '/v1/devices', query: query, body: body);
  Future<dynamic> notificationsControllerDevice({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/devices', query: query, body: body);
  Future<dynamic> notificationsControllerAnnounce({
    required String store,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'POST',
    '/v1/stores/${Uri.encodeComponent(store)}/announcements',
    query: query,
    body: body,
  );
  Future<dynamic> trainingControllerList({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('GET', '/v1/training', query: query, body: body);
  Future<dynamic> trainingControllerSave({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/training', query: query, body: body);
  Future<dynamic> trainingControllerStart({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('POST', '/v1/media/uploads', query: query, body: body);
  Future<dynamic> trainingControllerStatus({
    required String id,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'GET',
    '/v1/media/uploads/${Uri.encodeComponent(id)}',
    query: query,
    body: body,
  );
  Future<dynamic> trainingControllerChunk({
    required String id,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'PUT',
    '/v1/media/uploads/${Uri.encodeComponent(id)}',
    query: query,
    body: body,
  );
  Future<dynamic> trainingControllerMedia({
    required String id,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'GET',
    '/v1/media/${Uri.encodeComponent(id)}',
    query: query,
    body: body,
  );
  Future<dynamic> reportingControllerOverview({
    Map<String, dynamic>? query,
    dynamic body,
  }) => request('GET', '/v1/reports/overview', query: query, body: body);
  Future<dynamic> reportingControllerExport({
    required String store,
    Map<String, dynamic>? query,
    dynamic body,
  }) => request(
    'GET',
    '/v1/reports/stores/${Uri.encodeComponent(store)}/sales.csv',
    query: query,
    body: body,
  );
}
