import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intl/intl.dart' show NumberFormat;

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
    final wording = locale == 'fr' ? text.$2 : text.$1;
    // `{units:unit|units}`: the count and the word that goes with it (French: 0 and 1 are singular).
    var line = wording.replaceAllMapped(
      RegExp(r'\{(\w+):([^|}]*)\|([^}]*)\}'),
      (m) {
        final n = num.tryParse('${params[m[1]!] ?? ''}');
        if (n == null) return '';
        final singular = locale == 'fr' ? n.abs() < 2 : n == 1;
        return '${NumberFormat.decimalPattern(locale).format(n)} '
            '${singular ? m[2] : m[3]}';
      },
    );
    params.forEach((name, value) {
      final shown = name == 'amountMillimes' && value is num
          ? Money.format(value.toInt(), locale)
          : name == 'day' && value is String
          ? value.split('-').reversed.join('/')
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
    // A note the wording does not already show is added at the end.
    final note = params['note'];
    if (note is String && note.trim().isNotEmpty && !wording.contains('{note}'))
      line = '$line — ${note.trim()}';
    return line;
  }

  static const _errors = <String, _Text>{
    'ACCOUNT_DELETED': (
      'This account was deleted by its owner and cannot be used again.',
      'Ce compte a été supprimé par son titulaire et ne peut plus être utilisé.',
    ),
    'LAST_ADMIN': (
      'You are the only admin. Create another admin account before deleting yours.',
      'Vous êtes le seul administrateur. Créez un autre compte administrateur avant de supprimer le vôtre.',
    ),
    'REGION_NOT_EMPTY': (
      'This region still holds stores, groups, grossistes or people. Move them elsewhere first.',
      'Cette région contient encore des magasins, groupes, grossistes ou personnes. Déplacez-les d’abord.',
    ),
    'REGION_NAME_TAKEN': (
      'A region already has this name.',
      'Une région porte déjà ce nom.',
    ),
    'REGION_MOVE_BLOCKED': (
      'It still has restocks, counts or recount requests waiting. Finish or cancel them first.',
      'Il a encore des réassorts, comptages ou demandes de recomptage en attente. Terminez-les ou annulez-les d’abord.',
    ),
    'SAME_REGION': (
      'It already belongs to this region.',
      'Il appartient déjà à cette région.',
    ),
    'GROUP_OTHER_REGION': (
      'Choose a group of the new region.',
      'Choisissez un groupe de la nouvelle région.',
    ),
    'NOT_A_RESPONSABLE': (
      'Only a responsable can be moved this way.',
      'Seul un responsable peut être déplacé ainsi.',
    ),
    'WALLET_NOT_EMPTY': (
      'This person still has rewards in their wallet. Pay them out first, then they can stop selling.',
      'Cette personne a encore des récompenses dans son portefeuille. Payez-la d’abord, elle pourra ensuite arrêter de vendre.',
    ),
    'DUTIES_REQUIRED': (
      'A team member sells, buys, or both.',
      'Un membre de l’équipe vend, achète, ou les deux.',
    ),
    'TEMP_PASSWORD_EXPIRED': (
      'This temporary password has expired. Ask your manager to send you a new one.',
      'Ce mot de passe provisoire a expiré. Demandez un nouveau mot de passe à votre responsable.',
    ),
    'PASSWORD_CHANGE_REQUIRED': (
      'Choose your own password first.',
      'Choisissez d’abord votre propre mot de passe.',
    ),
    'REGION_REQUIRED': ('Choose a region.', 'Choisissez une région.'),
    'REGION_NOT_FOUND': (
      'This region no longer exists.',
      'Cette région n’existe plus.',
    ),
    'DEPOT_OTHER_REGION': (
      'This grossiste works for another region.',
      'Ce grossiste travaille pour une autre région.',
    ),
    'TOO_MANY_PHOTOS': (
      'Add between 1 and 5 different photos or documents.',
      'Ajoutez entre 1 et 5 photos ou documents différents.',
    ),
    'WEB_STAFF_ONLY': (
      'This page is for administrators and responsables. Please use the BioBalance app on your phone.',
      'Cette page est réservée aux administrateurs et aux responsables. Utilisez l’application BioBalance sur votre téléphone.',
    ),
    'INVALID_CREDENTIALS': (
      'Incorrect email or password.',
      'E-mail ou mot de passe incorrect.',
    ),
    'DEMO_ACCOUNT': (
      'This is a demonstration account: its password cannot be changed.',
      'Ceci est un compte de démonstration : son mot de passe ne peut pas être modifié.',
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
    'SALE_OUTSIDE_HOURS': (
      'This sale was made outside the working hours, so it cannot be recorded. Remove it from the list.',
      'Cette vente a été faite en dehors des heures de travail : elle ne peut pas être enregistrée. Retirez-la de la liste.',
    ),
    'SERVER_CLOSED': (
      'BioBalance is closed for now.',
      'BioBalance est fermé pour le moment.',
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
    'EMAIL_TYPO': (
      'This email address looks mistyped (for example “gamail” instead of “gmail”). Check it.',
      'Cette adresse e-mail semble mal écrite (par exemple « gamail » au lieu de « gmail »). Vérifiez-la.',
    ),
    'REGION_HAS_RESPONSABLE': (
      'This region already has a responsable: swap the two, or move that one first.',
      'Cette région a déjà un responsable : échangez les deux, ou déplacez-le d’abord.',
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
    'OUT_OF_STOCK': (
      'Not enough stock for this sale.',
      'Stock insuffisant pour cette vente.',
    ),
    'BELOW_SOLD': (
      'You cannot do this: some of these units were already sold (or shipped), so they cannot be removed.',
      'Impossible : une partie de ces unités a déjà été vendue (ou expédiée), elle ne peut pas être retirée.',
    ),
    'PHONE_REQUIRED': (
      'Enter the phone number: the codes are sent by WhatsApp too.',
      'Saisissez le numéro de téléphone : les codes sont aussi envoyés par WhatsApp.',
    ),
    'PHONE_INVALID': (
      'Enter a Tunisian mobile number: 8 digits, with or without +216 or 00216.',
      'Saisissez un mobile tunisien : 8 chiffres, avec ou sans +216 ou 00216.',
    ),
    'STALE_COUNT': (
      'This count was changed by someone else meanwhile. Go back and open it again.',
      'Ce comptage a été modifié entre-temps par quelqu’un d’autre. Revenez en arrière et rouvrez-le.',
    ),
    'CORRECTION_NOT_APPROVED': (
      'Ask the admin to approve a correction first.',
      'Demandez d’abord l’accord de l’admin pour corriger.',
    ),
    'CORRECTION_PENDING': (
      'A correction was already asked for this count.',
      'Une correction a déjà été demandée pour ce comptage.',
    ),
    'DELIVER_LATER_STORE_ONLY': (
      'A grossiste’s delivery is recorded when it arrives.',
      'La livraison d’un grossiste s’enregistre à son arrivée.',
    ),
    'EDITING': (
      'This count is being corrected: wait for the responsable to finish.',
      'Ce comptage est en cours de correction : attendez que le responsable ait terminé.',
    ),
    'REASON_REQUIRED': (
      'Say what was wrong: correcting an approved count needs a reason.',
      'Dites ce qui n’allait pas : corriger un comptage approuvé demande un motif.',
    ),
    'STOCK_CORRECTION_CLOSED': (
      'A count can be corrected for 3 days after its approval. Ask the admin.',
      'Un comptage peut être corrigé pendant 3 jours après son approbation. Demandez à l’admin.',
    ),
    'NOT_LATEST': (
      'A newer count of this place exists: correct that one.',
      'Un comptage plus récent de ce lieu existe : corrigez celui-là.',
    ),
    'SUPPLIER_CHOICE_OFF': (
      'You cannot choose the grossiste for an order: the admin decides.',
      'Vous ne pouvez pas choisir le grossiste d’une commande : l’admin décide.',
    ),
    'DECISION_LOCKED': (
      'A decision can only be changed for 6 hours after it was made.',
      'Une décision ne peut être modifiée que pendant 6 heures après avoir été prise.',
    ),
    'HAS_ACTIVITY': (
      'This store already sold something: suspend it instead.',
      'Ce magasin a déjà vendu : suspendez-le plutôt.',
    ),
    'DECLARATION_EXISTS': (
      'This place was counted again since: that count stands.',
      'Ce lieu a été recompté depuis : ce comptage fait foi.',
    ),
    'ALREADY_COUNTED': (
      'The stock of this place was already declared.',
      'Le stock de ce lieu a déjà été déclaré.',
    ),
    'ALREADY_ACTIVATED': (
      'This person already has an account. Deactivate it instead.',
      'Cette personne a déjà un compte. Désactivez-le plutôt.',
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
    'PHOTO_REQUIRED': (
      'Add a photo or a document first.',
      'Ajoutez d’abord une photo ou un document.',
    ),
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
    'REWARD_TOO_HIGH': (
      'A reward above 100 TND per unit is refused. Check the amount: it is in TND, not millimes.',
      'Une récompense de plus de 100 TND par unité est refusée. Vérifiez le montant : il est en TND, pas en millimes.',
    ),
    'REWARD_CONFIRMATION_REQUIRED': (
      'This reward is above 10 TND per unit. Confirm it is not a typo.',
      'Cette récompense dépasse 10 TND par unité. Confirmez que ce n’est pas une faute de frappe.',
    ),
    'POSITION_REASON_REQUIRED': (
      'The position does not match this place: say why.',
      'La position ne correspond pas à ce lieu : dites pourquoi.',
    ),
    'VISIT_OVERLAP': (
      'Another visit covers some of this time.',
      'Une autre visite couvre une partie de ce créneau.',
    ),
    'TOO_MANY_VISITS': (
      'That day already has twenty visits.',
      'Ce jour compte déjà vingt visites.',
    ),
    'INVALID_LEAD': (
      'Choose none, 15, 30, 60 or 120 minutes.',
      'Choisissez aucun, 15, 30, 60 ou 120 minutes.',
    ),
    'PLACE_NOT_FOUND': (
      'Choose a store or a grossiste of your region.',
      'Choisissez un point de vente ou un grossiste de votre région.',
    ),
    'PLACE_INACTIVE': ('This place is not active.', 'Ce lieu n’est pas actif.'),
    'TOO_EARLY': (
      'You can start a visit one hour before it begins.',
      'Vous pouvez commencer une visite une heure avant son début.',
    ),
    'WRONG_DAY': (
      'This visit was planned for another day.',
      'Cette visite était prévue un autre jour.',
    ),
    'POSITION_FIXED': (
      'This place already has a position. Ask the admin to change it.',
      'Ce lieu a déjà une position. Demandez à l’administrateur de la changer.',
    ),
    'LOW_ACCURACY': (
      'The position is not precise enough. Wait for a better signal, outdoors if you can.',
      'La position n’est pas assez précise. Attendez un meilleur signal, dehors si possible.',
    ),
    'OUTSIDE_TUNISIA': (
      'This position is outside Tunisia.',
      'Cette position est hors de Tunisie.',
    ),
    'NOT_SAME_GROUP': (
      'Only paras of the same group can exchange products.',
      'Seuls les paras d’un même groupe peuvent s’échanger des produits.',
    ),
    'SAME_PLACE': (
      'Choose two different paras.',
      'Choisissez deux paras différents.',
    ),
    'GROUP_INACTIVE': (
      'The group is not active.',
      'Le groupe n’est pas actif.',
    ),
    'PARA_NOT_FOUND': ('Unknown para.', 'Para inconnu.'),
    'INVALID_QUANTITY': (
      'Quantities are whole numbers above zero.',
      'Les quantités sont des nombres entiers supérieurs à zéro.',
    ),
    'TRANSFER_STOCK': (
      'A para does not hold enough of these products.',
      'Un para n’a pas assez de ces produits.',
    ),
    'RETURN_STOCK': (
      'A para does not hold enough of these products.',
      'Un para n’a pas assez de ces produits.',
    ),
    'INVALID_ACTION': (
      'This action does not fit: a move needs the receiving para.',
      'Cette action ne convient pas : un déplacement demande le para qui reçoit.',
    ),
    'NOTHING_TO_REPRICE': (
      'The rates of that day already match this sale.',
      'Les tarifs de ce jour correspondent déjà à cette vente.',
    ),
    'PAYOUT_STEP': (
      'A payout is requested in multiples of 5 TND.',
      'Un paiement se demande par multiples de 5 TND.',
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
      'This file is too large (12 MB at most for a photo or a document).',
      'Ce fichier est trop volumineux (12 Mo au plus pour une photo ou un document).',
    ),
    'UNSUPPORTED_FILE': (
      'This file type is not supported. Use a photo (JPEG, PNG) or a PDF.',
      'Ce type de fichier n’est pas pris en charge. Utilisez une photo (JPEG, PNG) ou un PDF.',
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

  /// The wording table, for the test that keeps it equal to the server's copy
  /// (apps/api/src/core/notice-text.json, used for iPhone push alerts).
  @visibleForTesting
  static Map<String, (String, String)> get notificationTexts => _notifications;

  static const _notifications = <String, _Text>{
    'account.deleted': (
      '{name} deleted their account. Their sales and history stay, without their name.',
      '{name} a supprimé son compte. Ses ventes et son historique restent, sans son nom.',
    ),
    'pdv.moved.in': (
      '{name} joined your region, from {from}, with its team and stock.',
      '{name} rejoint votre région, depuis {from}, avec son équipe et son stock.',
    ),
    'pdv.moved.out': (
      '{name} moved to {to}.',
      '{name} est passé dans la région {to}.',
    ),
    'group.moved.in': (
      'The group {name} joined your region, from {from}.',
      'Le groupe {name} rejoint votre région, depuis {from}.',
    ),
    'group.moved.out': (
      'The group {name} moved to {to}.',
      'Le groupe {name} est passé dans la région {to}.',
    ),
    'depot.moved.in': (
      'The grossiste {name} joined your region, from {from}.',
      'Le grossiste {name} rejoint votre région, depuis {from}.',
    ),
    'depot.moved.out': (
      'The grossiste {name} moved to {to}.',
      'Le grossiste {name} est passé dans la région {to}.',
    ),
    'responsable.moved': (
      'You now look after {region}.',
      'Vous vous occupez maintenant de {region}.',
    ),
    'restock.assigned': (
      'Restock {number} will be shipped from {depot}.',
      'Le réassort {number} sera expédié depuis {depot}.',
    ),
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
      '{name} was approved: the sign-in details were sent by email and WhatsApp.',
      '{name} a été approuvé(e) : les identifiants sont envoyés par email et WhatsApp.',
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
    'sale.recorded': (
      '{seller} sold {units:unit|units} at {place} · {amount} earned.',
      '{seller} a vendu {units:unité|unités} à {place} · {amount} gagnés.',
    ),
    'day.summary': (
      'Today in {region}: {sales:sale|sales}, {units:unit|units}, {amount} in rewards.',
      'Aujourd’hui, région {region} : {sales:vente|ventes}, {units:unité|unités}, {amount} de récompenses.',
    ),
    'day.summary_stock': (
      'Today in {region}: {sales:sale|sales}, {units:unit|units}, {amount} in rewards. {outOfStock:product is|products are} out of stock in its stores.',
      'Aujourd’hui, région {region} : {sales:vente|ventes}, {units:unité|unités}, {amount} de récompenses. {outOfStock:produit en rupture|produits en rupture} dans ses points de vente.',
    ),
    'day.summary_none': (
      'No sale was recorded today in {region}.',
      'Aucune vente enregistrée aujourd’hui, région {region}.',
    ),
    'day.network': (
      'Today in the network: {sales:sale|sales}, {units:unit|units}, {amount} in rewards.',
      'Aujourd’hui dans le réseau : {sales:vente|ventes}, {units:unité|unités}, {amount} de récompenses.',
    ),
    'course.published': (
      'New training: {title}.',
      'Nouvelle formation : {title}.',
    ),
    'reward.new': (
      'New reward from {day}: {amount} per unit of {target}.',
      'Nouvelle récompense à partir du {day} : {amount} par unité de {target}.',
    ),
    'stock.adjusted': (
      'The stock of {place} was corrected: {note}',
      'Le stock de {place} a été corrigé : {note}',
    ),
    'recount.requested': (
      '{by} asks to count {place} again.',
      '{by} demande de recompter {place}.',
    ),
    'recount.approved': (
      'A recount of {place} was allowed.',
      'Un nouveau comptage de {place} a été autorisé.',
    ),
    'recount.rejected': (
      'The recount of {place} was refused.',
      'Le nouveau comptage de {place} a été refusé.',
    ),
    'stock.submitted': (
      '{by} declared stock for {place}: waiting for approval.',
      '{by} a déclaré le stock de {place} : en attente d’approbation.',
    ),
    'stock.edited': (
      '{by} corrected the stock count of {place}: waiting for approval.',
      '{by} a corrigé le comptage du stock de {place} : en attente d’approbation.',
    ),
    'correction.requested': (
      '{by} asks to correct the approved count of {place}. Reason: {reason}',
      '{by} demande à corriger le comptage approuvé de {place}. Motif : {reason}',
    ),
    'correction.approved': (
      'The correction of the count of {place} was approved: you can make it now.',
      'La correction du comptage de {place} est approuvée : vous pouvez la faire maintenant.',
    ),
    'correction.rejected': (
      'The correction of the count of {place} was refused.',
      'La correction du comptage de {place} a été refusée.',
    ),
    'stock.admin_edited': (
      'The admin changed the stock count of {place}.',
      'L’admin a modifié le comptage du stock de {place}.',
    ),
    'stock.corrected': (
      '{by} corrected the approved stock count of {place}. Reason: {reason}',
      '{by} a corrigé le comptage approuvé du stock de {place}. Motif : {reason}',
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
    'restock.requested_from': (
      '{by} requested a restock {number} for {place}, from {depot}.',
      '{by} a demandé le réassort {number} pour {place}, depuis {depot}.',
    ),
    'supplier.allowed': (
      'You can now suggest the grossiste when you order a restock.',
      'Vous pouvez maintenant proposer le grossiste quand vous commandez un réassort.',
    ),
    'supplier.removed': (
      'You can no longer choose the grossiste for a restock: the admin decides.',
      'Vous ne pouvez plus choisir le grossiste d’un réassort : l’admin décide.',
    ),
    'decision.reopened': (
      'The admin took back a decision on {name}: it is waiting for a new decision.',
      'L’admin a repris une décision sur {name} : elle attend une nouvelle décision.',
    ),
    'stock.reopened': (
      'The count of {place} is back with the admin for a new decision.',
      'Le comptage de {place} est revenu chez l’admin pour une nouvelle décision.',
    ),
    'stock.amended': (
      'The admin corrected the approved count of {place}.',
      'L’admin a corrigé le comptage approuvé de {place}.',
    ),
    'restock.amended': (
      'The quantities received of restock {number} were corrected by the admin.',
      'Les quantités reçues du réassort {number} ont été corrigées par l’admin.',
    ),
    'restock.reopened': (
      'Restock {number} was taken back by the admin and will be routed again.',
      'Le réassort {number} a été repris par l’admin et sera acheminé à nouveau.',
    ),
    'restock.proposed': (
      '{by} proposes to fulfil order {number} from {from}: waiting for your approval.',
      '{by} propose de traiter la commande {number} depuis {from} : en attente de votre approbation.',
    ),
    'restock.proposal_approved': (
      'Your proposal for order {number} was approved.',
      'Votre proposition pour la commande {number} a été approuvée.',
    ),
    'restock.proposal_refused': (
      'Your proposal for order {number} was refused: {note}',
      'Votre proposition pour la commande {number} a été refusée : {note}',
    ),
    'restock.delivered': (
      'Order {number} was delivered by {by}: confirm the receipt.',
      'La commande {number} a été livrée par {by} : confirmez la réception.',
    ),
    'orders.asks': (
      '{by} asks whether {place} needs anything.{message}',
      '{by} demande si {place} a besoin de quelque chose.{message}',
    ),
    'duties.changed': (
      '{by} changed what you do in your point of sale. Open the app to see it.',
      '{by} a changé ce que vous faites dans votre point de vente. Ouvrez l’application pour le voir.',
    ),
    'restock.to_prepare': (
      'Restock {number} was given to {depot}: ship it.',
      'Le réassort {number} a été confié à {depot} : expédiez-le.',
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
      'Send the delivery paper of restock {number} again.',
      'Renvoyez le bon de livraison du réassort {number}.',
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
    'visit.reminder': (
      'Visit at {time}: {place}.',
      'Visite à {time} : {place}.',
    ),
    'visit.tomorrow': (
      'Tomorrow: {count:visit|visits}, the first at {time} at {place}.',
      'Demain : {count:visite|visites}, la première à {time} à {place}.',
    ),
    'visit.missed': (
      'You did not start your visit to {place} on {day}.',
      'Vous n’avez pas commencé votre visite à {place} le {day}.',
    ),
    'transfer.requested': (
      '{by} recorded a transfer from {from} to {to}: {units:unit|units}, waiting for approval.',
      '{by} a enregistré un transfert de {from} vers {to} : {units:unité|unités}, en attente d’approbation.',
    ),
    'transfer.changed': (
      '{by} changed the quantities of transfer {number} ({from} → {to}): {units:unit|units} now.',
      '{by} a modifié les quantités du transfert {number} ({from} → {to}) : {units:unité|unités} maintenant.',
    ),
    'transfer.approved': (
      'Transfer {number} approved: {units:unit|units} moved from {from} to {to}.',
      'Transfert {number} approuvé : {units:unité|unités} déplacées de {from} vers {to}.',
    ),
    'transfer.rejected': (
      'Transfer {number} was refused: {note}',
      'Le transfert {number} a été refusé : {note}',
    ),
    'transfer.expired': (
      'Transfer {number} expired: nobody decided it in time.',
      'Le transfert {number} a expiré : personne ne l’a décidé à temps.',
    ),
    'return.requested': (
      '{by} asks to return {units:unit|units} from {para}: waiting for approval.',
      '{by} demande le retour de {units:unité|unités} de {para} : en attente d’approbation.',
    ),
    'return.changed': (
      '{by} changed the quantities of return {number} ({para}): {units:unit|units} now.',
      '{by} a modifié les quantités du retour {number} ({para}) : {units:unité|unités} maintenant.',
    ),
    'return.approved': (
      'Return {number} approved: {units:unit|units} taken out of {para}.',
      'Retour {number} approuvé : {units:unité|unités} retirées de {para}.',
    ),
    'return.rejected': (
      'Return {number} was refused: {note}',
      'Le retour {number} a été refusé : {note}',
    ),
    'return.expired': (
      'Return {number} expired: nobody decided it in time.',
      'Le retour {number} a expiré : personne ne l’a décidé à temps.',
    ),
    'return.moved': (
      'Return {number}: {units:unit|units} moved from {para} to {to}.',
      'Retour {number} : {units:unité|unités} déplacées de {para} vers {to}.',
    ),
    'return.added': (
      'Return {number}: {units:unit|units} added to {para}.',
      'Retour {number} : {units:unité|unités} ajoutées à {para}.',
    ),
    'sale.repriced': (
      '{by} corrected the reward of one of your sales.',
      '{by} a corrigé la récompense de l’une de vos ventes.',
    ),
    'sale.reward.high': (
      '{seller} earned {amount} on one sale at {place}. Check the reward rates.',
      '{seller} a gagné {amount} sur une seule vente à {place}. Vérifiez les tarifs de récompense.',
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
