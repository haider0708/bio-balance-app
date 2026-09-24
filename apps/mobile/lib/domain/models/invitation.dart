import 'models.dart';

class Invitation {
  final String id, email, kind, status, expiresAt;
  final String? acceptedAt;
  final List<String> storeIds;
  final int version;
  Invitation.fromJson(Json value)
    : id = value['id'],
      email = value['email'],
      kind = value['kind'],
      status = value['status'],
      expiresAt = value['expiresAt'],
      acceptedAt = value['acceptedAt'],
      version = integer(value['version']),
      storeIds = List.unmodifiable(List<String>.from(value['storeIds']));
  bool get canResend => ['pending', 'expired', 'revoked'].contains(status);
  bool get canRevoke => ['pending', 'expired'].contains(status);
  bool get canArchive => status != 'archived';
  String get statusLabel => switch (status) {
    'pending' => 'En attente',
    'expired' => 'Expirée',
    'accepted' => 'Acceptée',
    'revoked' => 'Révoquée',
    'replaced' => 'Remplacée',
    'archived' => 'Retirée de la liste',
    _ => 'Terminée',
  };
  String get roleLabel => switch (kind) {
    'new_group' => 'Responsable · création de groupe',
    'responsible' => 'Responsable · tout le groupe',
    'salesperson' => 'Vendeur · un magasin',
    _ => 'Invitation existante',
  };
}
