import '../../l10n/app_localizations.dart';
import '../api/api_exception.dart';
import '../util/money.dart';

typedef _Text = (String en, String fr);

/// Wording for what the server tells us: an error code or a system notification key.
/// The server sends stable codes; every sentence people read lives here, in both languages.
class ServerText {
  const ServerText._();

  static String error(AppLocalizations t, ApiException error) {
    final text = _errors[error.code];
    if (text == null) {
      if (error.status != null && error.status! >= 500) return t.errorServer;
      return t.errorGeneric;
    }
    return t.localeName == 'fr' ? text.$2 : text.$1;
  }

  /// A notification line, with `{placeholders}` filled from [params].
  static String notification(
    String locale,
    String key,
    Map<String, dynamic> params, {
    String? fallback,
  }) {
    final text = _notifications[key];
    if (text == null) return fallback ?? key;
    var line = locale == 'fr' ? text.$2 : text.$1;
    params.forEach((name, value) {
      final shown = name == 'amountMillimes' && value is num
          ? Money.format(value.toInt(), locale)
          : '${value ?? ''}';
      line = line.replaceAll(
        '{${name == 'amountMillimes' ? 'amount' : name}}',
        shown,
      );
    });
    line = line
        .replaceAll(RegExp(r'\{\w+\}'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final note = params['note'];
    if (note is String && note.trim().isNotEmpty)
      line = '$line — ${note.trim()}';
    return line;
  }

  static const _errors = <String, _Text>{
    'INVALID_CREDENTIALS': (
      'Incorrect email or password.',
      'E-mail ou mot de passe incorrect.',
    ),
    'MFA_REQUIRED': (
      'Enter the code from your authenticator app.',
      'Saisissez le code de votre application d’authentification.',
    ),
    'INVALID_MFA': (
      'That code is invalid or was already used.',
      'Ce code est invalide ou déjà utilisé.',
    ),
    'TOO_MANY_ATTEMPTS': (
      'Too many attempts. Try again in 15 minutes.',
      'Trop de tentatives. Réessayez dans 15 minutes.',
    ),
    'ACCESS_DISABLED': (
      'Your account is not active.',
      'Votre compte n’est pas actif.',
    ),
    'SESSION_EXPIRED': (
      'Your session ended. Please sign in again.',
      'Votre session a expiré. Reconnectez-vous.',
    ),
    'NOT_APPROVED': (
      'This account is not approved yet.',
      'Ce compte n’est pas encore approuvé.',
    ),
    'INVALID_CODE': (
      'This code is invalid or has expired.',
      'Ce code est invalide ou a expiré.',
    ),
    'FORBIDDEN': ('You cannot do this.', 'Vous ne pouvez pas faire cela.'),
    'NOT_FOUND': ('This item no longer exists.', 'Cet élément n’existe plus.'),
    'VALIDATION': (
      'Check the information you entered.',
      'Vérifiez les informations saisies.',
    ),
    'EMAIL_TAKEN': (
      'This email already has an account.',
      'Cet e-mail a déjà un compte.',
    ),
    'REGION_HAS_RESPONSABLE': (
      'This region already has a responsable.',
      'Cette région a déjà un responsable.',
    ),
    'GROUP_NOT_FOUND': (
      'Choose one of your groups.',
      'Choisissez l’un de vos groupes.',
    ),
    'PDV_NOT_FOUND': (
      'Point of sale not found.',
      'Point de vente introuvable.',
    ),
    'NOTE_REQUIRED': (
      'Please explain your decision.',
      'Expliquez votre décision.',
    ),
    'INVALID_STATE': (
      'This was already handled. Refresh to see the latest.',
      'C’est déjà traité. Actualisez pour voir la dernière version.',
    ),
    'SELF_ACTION': (
      'You cannot change your own access.',
      'Vous ne pouvez pas modifier votre propre accès.',
    ),
    'DECLARATION_PENDING': (
      'A stock declaration is already waiting for approval.',
      'Une déclaration de stock attend déjà son approbation.',
    ),
    'PHOTO_REQUIRED': ('Add a photo first.', 'Ajoutez d’abord une photo.'),
    'PRODUCT_NOT_FOUND': (
      'That product is not available.',
      'Ce produit n’est pas disponible.',
    ),
    'DUPLICATE_PRODUCT': (
      'A product appears twice.',
      'Un produit apparaît deux fois.',
    ),
    'DEPOT_NOT_FOUND': (
      'Choose an active grossiste.',
      'Choisissez un grossiste actif.',
    ),
    'TOO_MANY': (
      'You cannot ship more than was requested.',
      'Vous ne pouvez pas expédier plus que demandé.',
    ),
    'INSUFFICIENT_STOCK': (
      'Your depot does not hold enough of a product.',
      'Votre dépôt n’a pas assez d’un produit.',
    ),
    'NOTHING_SHIPPED': (
      'Ship at least one unit.',
      'Expédiez au moins une unité.',
    ),
    'RECEIVER_INVALID': (
      'Choose an active member of this point of sale.',
      'Choisissez un membre actif de ce point de vente.',
    ),
    'LINE_MISSING': (
      'Enter the quantity received for every product.',
      'Saisissez la quantité reçue pour chaque produit.',
    ),
    'DESTINATION_REQUIRED': (
      'Choose a point of sale.',
      'Choisissez un point de vente.',
    ),
    'PDV_INACTIVE': (
      'Your point of sale is not active yet.',
      'Votre point de vente n’est pas encore actif.',
    ),
    'INVALID_DATE': (
      'That date is not allowed.',
      'Cette date n’est pas autorisée.',
    ),
    'NO_LINES': ('Add at least one product.', 'Ajoutez au moins un produit.'),
    'CORRECTION_WINDOW_CLOSED': (
      'A sale can be corrected for 48 hours. Ask your responsable.',
      'Une vente se corrige pendant 48 heures. Demandez à votre responsable.',
    ),
    'RULE_OVERLAP': (
      'Another value already covers some of these days.',
      'Une autre valeur couvre déjà certains de ces jours.',
    ),
    'TARGET_REQUIRED': (
      'Choose a product or a family.',
      'Choisissez un produit ou une famille.',
    ),
    'FAMILY_NOT_FOUND': ('Unknown family.', 'Famille inconnue.'),
    'INVALID_PERIOD': (
      'The end date is before the start date.',
      'La date de fin précède la date de début.',
    ),
    'AMOUNT_TOO_LARGE': (
      'This amount is too large.',
      'Ce montant est trop élevé.',
    ),
    'INSUFFICIENT_BALANCE': (
      'The amount is higher than the available balance.',
      'Le montant dépasse le solde disponible.',
    ),
    'NO_RECIPIENTS': (
      'Nobody is in this audience yet.',
      'Personne ne correspond à cette audience.',
    ),
    'ALREADY_SENT': (
      'This announcement was already sent.',
      'Cette annonce a déjà été envoyée.',
    ),
    'EMPTY_COURSE': (
      'Add at least one lesson first.',
      'Ajoutez d’abord au moins une leçon.',
    ),
    'BODY_REQUIRED': (
      'Write the lesson text.',
      'Rédigez le texte de la leçon.',
    ),
    'VIDEO_REQUIRED': (
      'Add a video file or a link.',
      'Ajoutez une vidéo ou un lien.',
    ),
    'VIDEO_URL': (
      'The video link must start with https://.',
      'Le lien vidéo doit commencer par https://.',
    ),
    'PDF_REQUIRED': ('Upload the PDF.', 'Téléversez le PDF.'),
    'MEDIA_SCOPE': (
      'This file cannot be used here.',
      'Ce fichier ne peut pas être utilisé ici.',
    ),
    'ORDER_INVALID': (
      'The order must list every item once.',
      'L’ordre doit lister chaque élément une fois.',
    ),
    'FILE_TOO_LARGE': (
      'This file is too large.',
      'Ce fichier est trop volumineux.',
    ),
    'UNSUPPORTED_FILE': (
      'This file type is not supported.',
      'Ce type de fichier n’est pas pris en charge.',
    ),
    'EMPTY_FILE': ('The file is empty.', 'Le fichier est vide.'),
    'STORAGE_LOW': (
      'The server is low on storage. Try again later.',
      'Le serveur manque d’espace. Réessayez plus tard.',
    ),
    'UPLOAD_ABORTED': (
      'The upload was interrupted. Try again.',
      'Le téléversement a été interrompu. Réessayez.',
    ),
    'DUPLICATE': ('This already exists.', 'Cela existe déjà.'),
    'RETRY_LATER': (
      'The system is busy. Try again.',
      'Le système est occupé. Réessayez.',
    ),
    'AUTH_BUSY': (
      'Sign-in is busy. Try again in a moment.',
      'La connexion est occupée. Réessayez dans un instant.',
    ),
    'TIMEOUT': (
      'The server took too long. Try again.',
      'Le serveur met trop de temps. Réessayez.',
    ),
    'HTTP_413': (
      'This file or request is too large.',
      'Ce fichier ou cette demande est trop volumineux.',
    ),
    'HTTP_429': (
      'Too many requests. Wait a moment.',
      'Trop de demandes. Patientez un instant.',
    ),
  };

  static const _notifications = <String, _Text>{
    'group.submitted': (
      '{by} created the group “{name}”: waiting for approval.',
      '{by} a créé le groupe « {name} » : en attente d’approbation.',
    ),
    'group.approved': (
      'The group “{name}” was approved.',
      'Le groupe « {name} » a été approuvé.',
    ),
    'group.rejected': (
      'The group “{name}” was rejected.',
      'Le groupe « {name} » a été refusé.',
    ),
    'group.suspended': (
      'The group “{name}” was suspended.',
      'Le groupe « {name} » a été suspendu.',
    ),
    'group.reactivated': (
      'The group “{name}” is active again.',
      'Le groupe « {name} » est de nouveau actif.',
    ),
    'pdv.submitted': (
      '{by} created the point of sale “{name}”: waiting for approval.',
      '{by} a créé le point de vente « {name} » : en attente d’approbation.',
    ),
    'pdv.approved': (
      'The point of sale “{name}” was approved.',
      'Le point de vente « {name} » a été approuvé.',
    ),
    'pdv.rejected': (
      'The point of sale “{name}” was rejected.',
      'Le point de vente « {name} » a été refusé.',
    ),
    'pdv.suspended': (
      'The point of sale “{name}” was suspended.',
      'Le point de vente « {name} » a été suspendu.',
    ),
    'pdv.reactivated': (
      'The point of sale “{name}” is active again.',
      'Le point de vente « {name} » est de nouveau actif.',
    ),
    'member.submitted': (
      '{by} added {name} to {pdv}: waiting for approval.',
      '{by} a ajouté {name} à {pdv} : en attente d’approbation.',
    ),
    'member.approved': (
      '{name} was approved and received an invitation.',
      '{name} a été approuvé(e) et reçoit une invitation.',
    ),
    'member.rejected': (
      '{name} was not approved.',
      '{name} n’a pas été approuvé(e).',
    ),
    'member.suspended': (
      '{name} was deactivated.',
      '{name} a été désactivé(e).',
    ),
    'member.reactivated': (
      '{name} is active again.',
      '{name} est de nouveau actif(ve).',
    ),
    'stock.submitted': (
      '{by} declared stock for {place}: waiting for approval.',
      '{by} a déclaré le stock de {place} : en attente d’approbation.',
    ),
    'stock.approved': (
      'The stock of {place} was approved.',
      'Le stock de {place} a été approuvé.',
    ),
    'stock.rejected': (
      'The stock of {place} was rejected.',
      'Le stock de {place} a été refusé.',
    ),
    'restock.requested': (
      '{by} requested a restock {number} for {place}.',
      '{by} a demandé le réassort {number} pour {place}.',
    ),
    'restock.assigned': (
      'Restock {number} was assigned to {depot}.',
      'Le réassort {number} a été confié à {depot}.',
    ),
    'restock.to_prepare': (
      'Restock {number} is waiting for you to prepare it.',
      'Le réassort {number} attend votre préparation.',
    ),
    'restock.shipped': (
      'Restock {number} is on its way from {from}.',
      'Le réassort {number} est en route depuis {from}.',
    ),
    'restock.shipped_info': (
      '{by} shipped restock {number}.',
      '{by} a expédié le réassort {number}.',
    ),
    'restock.receiver_assigned': (
      'You were chosen to receive restock {number}.',
      'Vous êtes chargé(e) de recevoir le réassort {number}.',
    ),
    'restock.received': (
      '{by} sent the delivery paper for restock {number}: waiting for approval.',
      '{by} a envoyé le bon de livraison du réassort {number} : en attente d’approbation.',
    ),
    'restock.completed': (
      'Restock {number} is complete and the stock is updated.',
      'Le réassort {number} est terminé et le stock est mis à jour.',
    ),
    'restock.receipt_rejected': (
      'The receipt of restock {number} must be redone.',
      'La réception du réassort {number} est à refaire.',
    ),
    'restock.cancelled': (
      'Restock {number} was cancelled.',
      'Le réassort {number} a été annulé.',
    ),
    'sale.corrected': (
      '{by} corrected one of your sales.',
      '{by} a corrigé l’une de vos ventes.',
    ),
    'sale.voided': (
      '{by} cancelled one of your sales.',
      '{by} a annulé l’une de vos ventes.',
    ),
    'payout.requested': (
      '{name} asked for a payout of {amount}.',
      '{name} demande un paiement de {amount}.',
    ),
    'payout.approved': (
      'Your payout of {amount} was approved.',
      'Votre paiement de {amount} a été approuvé.',
    ),
    'payout.rejected': (
      'Your payout request of {amount} was declined.',
      'Votre demande de paiement de {amount} a été refusée.',
    ),
  };
}
