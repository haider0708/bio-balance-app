import '../models/models.dart';

abstract class WorkspaceRepository {
  Future<List<Store>> stores(UserAccount user, {bool refresh = false});
  Future<StoreData?> load(UserAccount user, Store store);
  Future<void> refresh(UserAccount user, Store store);
  Future<void> enqueue(
    UserAccount user,
    Store store,
    Json operation,
    Json effect, {
    String? draftKey,
    List<String> supersedes = const [],
  });
  Future<int> pendingCount(String accountId);
  Future<void> synchronize(UserAccount user, Store store);
  Future<void> saveDraft(
    String accountId,
    String storeId,
    String key,
    Json value,
  );
  Future<Json?> draft(String accountId, String storeId, String key);
}
