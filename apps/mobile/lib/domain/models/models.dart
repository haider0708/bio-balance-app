import 'batch_declaration.dart';
import 'tunis_dates.dart';
import 'money.dart';

typedef Json = Map<String, dynamic>;
int integer(dynamic value) =>
    value is int ? value : int.tryParse('$value') ?? 0;
List<Json> objects(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

class UserAccount {
  final String id, name, email;
  final bool admin;
  const UserAccount({
    required this.id,
    required this.name,
    required this.email,
    required this.admin,
  });
  factory UserAccount.fromJson(Json v) => UserAccount(
    id: v['id'],
    name: v['name'],
    email: v['email'],
    admin: v['platformAdmin'] == true,
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'platformAdmin': admin,
  };
}

class Store {
  final String id, organizationId, organizationName, name, city;
  final List<String> permissions;
  final int onboardingStep;
  final String? imageId;
  Store.fromJson(Json v)
    : id = v['id'],
      organizationId = v['organizationId'],
      organizationName = v['organizationName'] ?? '',
      name = v['name'],
      city = v['city'] ?? '',
      permissions = List.unmodifiable(
        List<String>.from(v['permissions'] ?? []),
      ),
      onboardingStep = integer(v['onboardingStep']),
      imageId = v['imageId'];
  bool get canManage => permissions.contains('manage');
  bool get canSell => permissions.contains('sell') || canManage;
  Json toJson() => {
    'id': id,
    'organizationId': organizationId,
    'organizationName': organizationName,
    'name': name,
    'city': city,
    'permissions': permissions,
    'onboardingStep': onboardingStep,
    'imageId': imageId,
  };
}

class Product {
  final String id, name, reference, barcode, description;
  final String? imageId;
  final Json attributes;
  final bool active;
  late final String searchText = '$name $reference $barcode'.toLowerCase();
  bool matches(String normalizedQuery) => searchText.contains(normalizedQuery);
  Product.fromJson(Json v)
    : attributes = Map.unmodifiable(v),
      imageId = v['imageId'],
      id = v['id'],
      name = v['name'],
      reference = v['reference'],
      barcode = v['barcode'] ?? '',
      description = v['description'] ?? '',
      active = v['active'] != false;
}

class InventoryLot {
  final String id, productId, batch, expiry;
  final int sellable, damaged, version;
  InventoryLot.fromJson(Json v)
    : id = v['id'],
      productId = v['productId'],
      batch = v['batch'],
      expiry = (v['expiry'] as String).substring(0, 10),
      sellable = integer(v['sellable']),
      damaged = integer(v['damaged']),
      version = integer(v['version']);
  bool expiredOn(String date) => expiry.compareTo(date) < 0;
  bool get expired => expiredOn(TunisDates.today());
  bool approachingOn(String date) =>
      !expiredOn(date) &&
      expiry.compareTo(
            TunisDates.civil(
              DateTime.parse('${date}T00:00:00Z').add(const Duration(days: 30)),
            ),
          ) <=
          0;
}

class SaleLine {
  final String id, productId;
  final int quantity;
  final Money price;
  final List<Json> allocations;
  final List<BatchDeclaration> batchDeclarations;
  SaleLine({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.price,
    required List<Json> allocations,
    List<BatchDeclaration> batchDeclarations = const [],
  }) : batchDeclarations = List.unmodifiable(batchDeclarations),
       allocations = List.unmodifiable(
         allocations.map((a) => Map<String, dynamic>.unmodifiable(a)),
       );
  factory SaleLine.fromJson(Json v) => SaleLine(
    id: v['id'],
    productId: v['productId'],
    quantity: integer(v['quantity']),
    price: Money(integer(v['unitPriceMillimes'])),
    allocations: objects(v['allocations']),
    batchDeclarations: objects(v['batchDeclarations'])
        .map(BatchDeclaration.fromJson)
        .toList(),
  );
  Json toJson({bool transport = false}) => {
    'id': id,
    'productId': productId,
    'quantity': quantity,
    'unitPriceMillimes': price.millimes.toString(),
    'allocations': allocations,
    if (!transport && batchDeclarations.isNotEmpty)
      'batchDeclarations': batchDeclarations.map((b) => b.toJson()).toList(),
  };
}

class StoreData {
  final Json raw;
  StoreData(Json raw) : raw = Map.unmodifiable(raw);
  late final List<Product> products = List.unmodifiable(
    objects(raw['products']).map(Product.fromJson),
  );
  late final Map<String, Product> productsById = Map.unmodifiable({
    for (final product in products) product.id: product,
  });
  late final Map<String, Product> _productsByBarcode = Map.unmodifiable({
    for (final product in products.reversed)
      if (product.active && product.barcode.isNotEmpty)
        product.barcode: product,
  });
  Product? productForBarcode(String code) {
    final exact = _productsByBarcode[code];
    if (exact != null) return exact;
    // iOS may report UPC-A as EAN-13 with a leading zero. Preserve the
    // original identifiers, and use this equivalent representation only as fallback.
    if (!RegExp(r'^\d{12,13}$').hasMatch(code)) return null;
    var checksum = 0, weight = 1;
    for (var i = code.length - 1; i >= 0; i--) {
      checksum += (code.codeUnitAt(i) - 48) * weight;
      weight = weight == 1 ? 3 : 1;
    }
    if (checksum % 10 != 0) return null;
    return code.length == 12
        ? _productsByBarcode['0$code']
        : code.startsWith('0')
        ? _productsByBarcode[code.substring(1)]
        : null;
  }

  late final List<InventoryLot> lots = List.unmodifiable(
    objects(raw['lots']).map(InventoryLot.fromJson),
  );
  late final Map<String, List<InventoryLot>> lotsByProduct = _groupLots();
  Map<String, List<InventoryLot>> _groupLots() {
    final grouped = <String, List<InventoryLot>>{};
    for (final lot in lots) {
      (grouped[lot.productId] ??= []).add(lot);
    }
    return grouped;
  }

  final Map<String, List<Json>> _lists = {};
  List<Json> list(String name) => _lists.putIfAbsent(name, () {
    final items = objects(raw[name]);
    // Snapshot pages use record IDs; presentation must retain useful ordering.
    if (['claims', 'orders', 'deliveries'].contains(name)) {
      items.sort((a, b) {
        if (name == 'claims' || name == 'orders') {
          bool pending(Json item) => name == 'claims'
              ? item['status'] == 'requested'
              : item['status'] != 'received';
          if (pending(a) != pending(b)) return pending(a) ? -1 : 1;
        }
        final key = name == 'deliveries' ? 'dispatchedAt' : 'createdAt';
        final first =
            DateTime.tryParse('${a[key]}')?.millisecondsSinceEpoch ?? 0;
        final second =
            DateTime.tryParse('${b[key]}')?.millisecondsSinceEpoch ?? 0;
        final date = second.compareTo(first);
        return date != 0 ? date : '${a['id']}'.compareTo('${b['id']}');
      });
    } else if (name == 'rewards') {
      items.sort((a, b) => '${a['title']}'.compareTo('${b['title']}'));
    }
    return List.unmodifiable(items);
  });
  late final Map<String, Json> _configIndex = {
    for (final c in list('config')) c['productId']: c,
  };
  Json config(String productId) =>
      _configIndex[productId] ??
      const {
        'priceMillimes': '0',
        'pointsPerUnit': 0,
        'threshold': 5,
        'pointsConfigured': false,
      };
  int get balance => integer((raw['points'] as Map?)?['balance']);
  int get reserved => integer((raw['points'] as Map?)?['reserved']);
  int get available => (balance - reserved).clamp(0, 1 << 53);
}

class AppFailure implements Exception {
  final String code, message;
  const AppFailure(this.code, this.message);
  @override
  String toString() => message;
}
