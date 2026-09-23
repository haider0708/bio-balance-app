import 'models.dart';

enum ScopeKind { network, group, store }

class PartnerGroup {
  final String id, name, status;
  final String? imageId, phone;
  final int version, storeCount;
  final bool canManage;
  const PartnerGroup({
    required this.id,
    required this.name,
    this.status = 'active',
    this.imageId,
    this.phone,
    this.version = 1,
    this.storeCount = 0,
    this.canManage = false,
  });
  factory PartnerGroup.fromJson(Json v) => PartnerGroup(
    id: v['id'],
    name: v['name'],
    status: v['status'] ?? 'active',
    imageId: v['imageId'],
    phone: v['phone'],
    version: integer(v['version'] ?? 1),
    storeCount: integer(v['storeCount']),
    canManage: v['canManage'] == true,
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'status': status,
    'imageId': imageId,
    'phone': phone,
    'version': version,
    'storeCount': storeCount,
    'canManage': canManage,
  };
}

class WorkspaceScope {
  final ScopeKind kind;
  final PartnerGroup? group;
  final Store? store;
  const WorkspaceScope.network()
    : kind = ScopeKind.network,
      group = null,
      store = null;
  const WorkspaceScope.group(PartnerGroup value)
    : kind = ScopeKind.group,
      group = value,
      store = null;
  WorkspaceScope.store(PartnerGroup parent, Store value)
    : kind = ScopeKind.store,
      group = parent,
      store = value {
    if (value.organizationId != parent.id) {
      throw const FormatException('Le magasin ne fait pas partie du groupe.');
    }
  }
  String get key => '${kind.name}:${group?.id ?? ''}:${store?.id ?? ''}';
}
