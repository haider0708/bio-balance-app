import '../api/json.dart';

enum Role {
  admin,
  responsable,
  vendeur,
  orders,
  acheteur;

  static Role parse(String value) => Role.values.firstWhere(
    (r) => r.name.toUpperCase() == value.toUpperCase(),
    orElse: () => Role.vendeur,
  );

  String get wire => name.toUpperCase();

  /// Works in a para: sells, buys, or both.
  bool get isTeam => this == vendeur || this == acheteur;
}

class Region {
  const Region({required this.id, required this.code, required this.name});

  factory Region.fromJson(Json j) =>
      Region(id: j.str('id'), code: j.str('code'), name: j.str('name'));

  final String id;
  final String code;
  final String name;
}

class Place {
  const Place({required this.id, required this.name});

  factory Place.fromJson(Json j) => Place(id: j.str('id'), name: j.str('name'));

  final String id;
  final String name;
}

/// The signed-in person.
class Me {
  const Me({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.locale,
    this.phone,
    this.region,
    this.pdv,
    this.canChooseSupplier = false,
    this.canOrder = false,
    this.mustChangePassword = false,
  });

  factory Me.fromJson(Json j) => Me(
    id: j.str('id'),
    name: j.str('name'),
    email: j.str('email'),
    phone: j.strOrNull('phone'),
    role: Role.parse(j.str('role')),
    locale: j.str('locale', 'fr'),
    region: j.objOrNull('region') == null
        ? null
        : Region.fromJson(j.obj('region')),
    pdv: j.objOrNull('pdv') == null ? null : Place.fromJson(j.obj('pdv')),
    canChooseSupplier: j['canChooseSupplier'] == true,
    canOrder: j['canOrder'] == true,
    mustChangePassword: j['mustChangePassword'] == true,
  );

  final String id;
  final String name;
  final String email;
  final String? phone;
  final Role role;
  final String locale;
  final Region? region;
  final Place? pdv;

  /// A responsable the admin lets suggest the grossiste of a restock (the switch is on too).
  final bool canChooseSupplier;

  /// Places and receives the orders of its para: a buyer always, a team member the responsable allowed.
  final bool canOrder;

  /// Signed in with the generated password: the app asks for their own before anything else.
  final bool mustChangePassword;

  /// A buyer, whether or not the account also sells.
  bool get isBuyer =>
      role == Role.acheteur || (role == Role.vendeur && canOrder);

  /// The first letters of the name, for avatars.
  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}
