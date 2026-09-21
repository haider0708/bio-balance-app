import 'package:uuid/uuid.dart';

import 'tunis_dates.dart';

class BatchDeclaration {
  final String lotId, productId, batch, expiry;
  const BatchDeclaration._(this.lotId, this.productId, this.batch, this.expiry);
  factory BatchDeclaration.create(
    String storeId,
    String productId,
    String batch,
    String expiry,
  ) {
    final normalizedBatch = batch.trim(),
        normalizedExpiry = TunisDates.expiry(expiry);
    if (normalizedBatch.isEmpty || normalizedBatch.length > 100) {
      throw const FormatException('Indiquez le numéro du lot.');
    }
    return BatchDeclaration._(
      identity(storeId, productId, normalizedBatch, normalizedExpiry),
      productId,
      normalizedBatch,
      normalizedExpiry,
    );
  }
  factory BatchDeclaration.fromJson(Map<String, dynamic> value) =>
      BatchDeclaration._(
        value['lotId'],
        value['productId'],
        value['batch'],
        value['expiry'],
      );
  static String identity(
    String store,
    String product,
    String batch,
    String expiry,
  ) => const Uuid().v5(
    '40cdd460-fdea-4c8f-9533-51a0843ecfff',
    '$store|$product|${batch.trim()}|${TunisDates.expiry(expiry)}',
  );
  Map<String, dynamic> toJson() => {
    'lotId': lotId,
    'productId': productId,
    'batch': batch,
    'expiry': expiry,
  };
}
