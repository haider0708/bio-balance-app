import '../../core/api/json.dart';
import '../../core/auth/me.dart';

enum ItemStatus {
  pending,
  active,
  rejected,
  suspended;

  static ItemStatus parse(String v) => ItemStatus.values.firstWhere(
    (s) => s.name.toUpperCase() == v,
    orElse: () => ItemStatus.pending,
  );
  String get wire => name.toUpperCase();
}

/// A region as the admin manages it: who looks after it and what it holds.
class RegionInfo {
  const RegionInfo({
    required this.id,
    required this.name,
    required this.pdvs,
    required this.groups,
    required this.grossistes,
    required this.members,
    required this.deletable,
    this.responsable,
  });

  factory RegionInfo.fromJson(Json j) => RegionInfo(
    id: j.str('id'),
    name: j.str('name'),
    pdvs: j.integer('pdvs'),
    groups: j.integer('groups'),
    grossistes: j.integer('grossistes'),
    members: j.integer('members'),
    deletable: j['deletable'] == true,
    responsable: j.objOrNull('responsable') == null
        ? null
        : Person.fromJson({
            ...j.obj('responsable'),
            'role': 'RESPONSABLE',
            'activated': true,
          }),
  );

  final String id;
  final String name;
  final int pdvs;
  final int groups;
  final int grossistes;
  final int members;

  /// Nothing left in it: only then can it be deleted.
  final bool deletable;
  final Person? responsable;
}

class Group {
  const Group({
    required this.id,
    required this.name,
    required this.status,
    required this.regionId,
    required this.pdvCount,
    this.decisionNote,
  });

  factory Group.fromJson(Json j) => Group(
    id: j.str('id'),
    name: j.str('name'),
    status: ItemStatus.parse(j.str('status')),
    regionId: j.str('regionId'),
    pdvCount: j.integer('pdvCount'),
    decisionNote: j.strOrNull('decisionNote'),
  );

  final String id;
  final String name;
  final ItemStatus status;
  final String regionId;
  final int pdvCount;
  final String? decisionNote;
}

/// A point of sale (PDV).
class Pdv {
  const Pdv({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.status,
    required this.regionId,
    required this.memberCount,
    required this.initialStock,
    this.phone,
    this.groupId,
    this.groupName,
    this.decisionNote,
  });

  factory Pdv.fromJson(Json j) => Pdv(
    id: j.str('id'),
    name: j.str('name'),
    address: j.str('address'),
    city: j.str('city'),
    phone: j.strOrNull('phone'),
    status: ItemStatus.parse(j.str('status')),
    regionId: j.str('regionId'),
    groupId: j.strOrNull('groupId'),
    groupName: j.strOrNull('groupName'),
    memberCount: j.integer('memberCount'),
    initialStock: j.str('initialStock', 'NONE'),
    decisionNote: j.strOrNull('decisionNote'),
  );

  final String id;
  final String name;
  final String address;
  final String city;
  final String? phone;
  final ItemStatus status;
  final String regionId;
  final String? groupId;
  final String? groupName;
  final int memberCount;

  /// NONE, PENDING, APPROVED or REJECTED: the state of its opening stock.
  final String initialStock;
  final String? decisionNote;

  bool get hasApprovedStock => initialStock == 'APPROVED';
}

/// A person with an account, as managers see them.
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.activated,
    this.phone,
    this.regionId,
    this.pdvId,
    this.decisionNote,
  });

  factory Person.fromJson(Json j) => Person(
    id: j.str('id'),
    name: j.str('name'),
    email: j.str('email'),
    phone: j.strOrNull('phone'),
    role: Role.parse(j.str('role')),
    status: ItemStatus.parse(j.str('status')),
    regionId: j.strOrNull('regionId'),
    pdvId: j.strOrNull('pdvId'),
    activated: j.flag('activated'),
    decisionNote: j.strOrNull('decisionNote'),
  );

  final String id;
  final String name;
  final String email;
  final String? phone;
  final Role role;
  final ItemStatus status;
  final String? regionId;
  final String? pdvId;
  final bool activated;
  final String? decisionNote;

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty
        ? '?'
        : parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

/// A grossiste: a warehouse of a region with its own stock. It has no account.
class Depot {
  const Depot({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    required this.regionId,
    required this.regionName,
    required this.active,
    this.phone,
    this.photoIds = const [],
    this.units = 0,
    this.products = 0,
    this.counted = false,
    this.countPending = false,
  });

  factory Depot.fromJson(Json j) => Depot(
    id: j.str('id'),
    name: j.str('name'),
    address: j.str('address'),
    city: j.str('city'),
    phone: j.strOrNull('phone'),
    regionId: j.obj('region').str('id'),
    regionName: j.obj('region').str('name'),
    active: j.str('status') == 'ACTIVE',
    photoIds: [for (final p in j.list('photoIds')) p as String],
    units: j.integer('units'),
    products: j.integer('products'),
    counted: j['counted'] == true,
    countPending: j['countPending'] == true,
  );

  final String id;
  final String name;
  final String address;
  final String city;
  final String? phone;
  final String regionId;
  final String regionName;
  final bool active;

  /// Up to five photos of the warehouse.
  final List<String> photoIds;

  /// What it holds now.
  final int units;
  final int products;

  /// Whether its first stock was entered and approved, and whether a count waits for the admin.
  final bool counted;
  final bool countPending;
}
