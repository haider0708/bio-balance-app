import '../../domain/models/models.dart';
import '../../domain/models/workspace_scope.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';
import 'offline_repository.dart';

class GroupCatalog {
  final List<PartnerGroup> groups;
  final List<String> grants;
  const GroupCatalog(this.groups, this.grants);
}

class GroupRepository {
  final RepositoryContext context;
  final OfflineRepository local;
  final String accountId;
  GroupRepository(this.context, this.local, this.accountId);
  Future<GroupCatalog> cached() async {
    final v = await local.draft(accountId, '', 'group-catalog');
    return GroupCatalog(
      objects(v?['items']).map(PartnerGroup.fromJson).toList(),
      List<String>.from(v?['grants'] ?? []),
    );
  }

  Future<GroupCatalog> refresh() => context.run(() async {
    final groups = <PartnerGroup>[];
    final grants = <String>{};
    String? after;
    do {
      final page = await context.api.groupList(after: after);
      groups.addAll(page.items.map((g) => PartnerGroup.fromJson(g.toJson())));
      grants.addAll(page.creationGrants.map((g) => g.id));
      after = page.nextCursor;
    } while (after != null);
    groups.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final result = GroupCatalog(
      List.unmodifiable(groups),
      List.unmodifiable(grants),
    );
    await context.run(
      () => local.saveDraft(accountId, '', 'group-catalog', {
        'items': groups.map((g) => g.toJson()).toList(),
        'grants': grants.toList(),
      }),
    );
    return result;
  });
  Future<PartnerGroup> create(Json v) => context.run(
    () async => PartnerGroup.fromJson(
      (await context.api.groupCreate(body: GroupCreateRequestDto.fromJson(v)))
          .toJson(),
    ),
  );
  Future<void> update(String id, Json v) => context.run(() async {
    await context.api.groupUpdate(
      id: id,
      body: GroupUpdateRequestDto.fromJson(v),
    );
  });
  Future<Json> lifecycleImpact(String id, {String? storeId}) => context.run(
    () async =>
        (await context.api.groupImpact(id: id, storeId: storeId)).toJson(),
  );
  Future<void> lifecycle(String id, Json body, {String? storeId}) =>
      context.run(() async {
        await context.api.groupLifecycle(
          id: id,
          storeId: storeId,
          body: GroupLifecycleRequestDto.fromJson(body),
        );
      });
  Future<Json> team(String id) =>
      context.run(() async => (await context.api.groupTeam(id: id)).toJson());
  Future<void> member(String id, String userId, Json v) =>
      context.run(() async {
        await context.api.groupMember(
          id: id,
          userId: userId,
          body: GroupMemberRequestDto.fromJson(v),
        );
      });
}
