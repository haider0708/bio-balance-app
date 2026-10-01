import 'models.dart';
import 'tunis_dates.dart';

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

  /// A code that can still be used is disabled; an expired or disabled one is relaunched.
  bool get canResend => ['pending', 'expired', 'revoked'].contains(status);
  bool get canRevoke => status == 'pending';
  bool get canRemove =>
      ['pending', 'expired', 'revoked', 'replaced', 'closed'].contains(status);

  /// Once the account exists the invitation is history: nothing can be done to it.
  bool get locked => status == 'accepted';
  String get statusLabel => switch (status) {
    'pending' => 'En attente',
    'expired' => 'Expirée',
    'accepted' => 'Compte créé',
    'revoked' => 'Désactivée',
    'replaced' => 'Remplacée',
    'archived' => 'Supprimée',
    _ => 'Terminée',
  };
  String get dateLabel {
    final accepted = acceptedAt;
    return switch (status) {
      'pending' => 'Valable jusqu’au ${TunisDates.timestampLabel(expiresAt)}',
      'expired' => 'Expirée le ${TunisDates.timestampLabel(expiresAt)}',
      'accepted' when accepted != null =>
        'Compte créé le ${TunisDates.timestampLabel(accepted)}',
      _ => '',
    };
  }

  String get roleLabel => switch (kind) {
    'new_group' => 'Responsable · création de groupe',
    'responsible' => 'Responsable · tout le groupe',
    'salesperson' => 'Vendeur · un magasin',
    'wholesaler' => 'Grossiste · stock et livraisons',
    _ => 'Invitation existante',
  };
}
