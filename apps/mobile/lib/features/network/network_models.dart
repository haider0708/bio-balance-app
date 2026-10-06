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

class Depot {
  const Depot({
    required this.id,
    required this.name,
    required this.address,
    required this.city,
    this.phone,
    this.regionId,
    this.regionName,
    this.grossisteName,
    this.grossistePhone,
    this.grossisteEmail,
  });

  factory Depot.fromJson(Json j) => Depot(
    id: j.str('id'),
    name: j.str('name'),
    address: j.str('address'),
    city: j.str('city'),
    phone: j.strOrNull('phone'),
    regionId: j.objOrNull('region')?.str('id'),
    regionName: j.objOrNull('region')?.str('name'),
    grossisteName: j.objOrNull('grossiste')?.str('name'),
    grossistePhone: j.objOrNull('grossiste')?.strOrNull('phone'),
    grossisteEmail: j.objOrNull('grossiste')?.str('email'),
  );

  final String id;
  final String name;
  final String address;
  final String city;
  final String? phone;
  final String? regionId;
  final String? regionName;
  final String? grossisteName;
  final String? grossistePhone;
  final String? grossisteEmail;
}
