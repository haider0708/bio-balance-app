// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get about => 'À propos';

  @override
  String get account => 'Compte';

  @override
  String get accountActivated => 'Compte activé. Vous pouvez vous connecter.';

  @override
  String get accountCreated => 'Compte créé et invitation envoyée';

  @override
  String get activateAccount => 'Activer mon compte';

  @override
  String get activateSubtitle =>
      'Saisissez l’e-mail et le code reçus, puis choisissez un mot de passe.';

  @override
  String get activateTitle => 'Activez votre compte';

  @override
  String get activationCode => 'Code d’activation';

  @override
  String get activePdvs => 'PDV actifs';

  @override
  String get activity => 'Activité';

  @override
  String get add => 'Ajouter';

  @override
  String get addLesson => 'Ajouter une leçon';

  @override
  String get addMember => 'Ajouter un membre';

  @override
  String get addMemberFromPdv =>
      'Ouvrez un point de vente pour ajouter un membre.';

  @override
  String get addMemberHint =>
      'Ils peuvent se connecter dès que BioBalance les approuve. Ils reçoivent un e-mail avec un code.';

  @override
  String get addProduct => 'Ajouter un produit';

  @override
  String addSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ajouter $count produits',
      one: 'Ajouter 1 produit',
      zero: 'Choisissez des produits',
    );
    return '$_temp0';
  }

  @override
  String addToSale(String name) {
    return 'Ajouter $name';
  }

  @override
  String addedToSale(String name) {
    return '$name ajouté';
  }

  @override
  String get address => 'Adresse';

  @override
  String get adjustQuantities => 'Ajuster les quantités';

  @override
  String get adjustQuantitiesHint =>
      'Modifiez ce qui sera envoyé avant de choisir qui l’envoie.';

  @override
  String get all => 'Tous';

  @override
  String get allCaughtUp => 'Tout est à jour.';

  @override
  String get allRegions => 'Toutes les régions';

  @override
  String get amendAndApprove => 'Corriger et approuver';

  @override
  String get amendReceiptHint =>
      'Comparez avec la photo du bon et corrigez une quantité si besoin.';

  @override
  String get amendStockHint =>
      'Modifiez une quantité si la photo montre autre chose.';

  @override
  String get amountPerUnit => 'Montant par unité vendue';

  @override
  String get amountPerUnitHint => 'Exemple : 0,500';

  @override
  String get amountTnd => 'Montant';

  @override
  String get announcement => 'Annonce';

  @override
  String get announcementScheduled => 'Annonce planifiée';

  @override
  String get announcementSent => 'Annonce envoyée';

  @override
  String get announcementsTitle => 'Annonces';

  @override
  String get appName => 'BioBalance';

  @override
  String get appVersion => 'Version';

  @override
  String approvalGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groupes',
      one: '1 groupe',
    );
    return '$_temp0';
  }

  @override
  String approvalMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membres',
      one: '1 membre',
    );
    return '$_temp0';
  }

  @override
  String approvalPayouts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paiements',
      one: '1 paiement',
    );
    return '$_temp0';
  }

  @override
  String approvalPdvs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points de vente',
      one: '1 point de vente',
    );
    return '$_temp0';
  }

  @override
  String approvalReceipts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count livraisons',
      one: '1 livraison',
    );
    return '$_temp0';
  }

  @override
  String approvalRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count demandes de réassort',
      one: '1 demande de réassort',
    );
    return '$_temp0';
  }

  @override
  String approvalStock(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stocks',
      one: '1 stock',
    );
    return '$_temp0';
  }

  @override
  String get approvalsTitle => 'Validations';

  @override
  String get approve => 'Approuver';

  @override
  String get approveAndInvite => 'Approuver et envoyer l’invitation';

  @override
  String get approveAsCounted => 'Approuver comme compté';

  @override
  String approveGroupTitle(String name) {
    return 'Approuver le groupe « $name » ?';
  }

  @override
  String get approved => 'Approuvé';

  @override
  String get askRecount => 'Demander un nouveau comptage';

  @override
  String get assignToGrossiste => 'Confier à un grossiste';

  @override
  String get auditTitle => 'Historique des modifications';

  @override
  String get authenticatorCode => 'Code d’authentification';

  @override
  String get authenticatorCodeHelp =>
      'Les 6 chiffres de votre application d’authentification.';

  @override
  String get availableBalance => 'Solde disponible';

  @override
  String availableUpTo(String amount) {
    return 'Jusqu’à $amount';
  }

  @override
  String get back => 'Retour';

  @override
  String get balanceShort => 'Solde';

  @override
  String get barcode => 'Code-barres';

  @override
  String get barcodeUnknown => 'Ce code-barres n’est pas dans le catalogue.';

  @override
  String get byDay => 'jour';

  @override
  String get byFamily => 'Par famille';

  @override
  String byName(String name) {
    return 'par $name';
  }

  @override
  String get byPdv => 'point de vente';

  @override
  String get byProduct => 'Par produit';

  @override
  String get byProductShort => 'produit';

  @override
  String get byRegion => 'région';

  @override
  String get bySeller => 'vendeur';

  @override
  String get cameraUnavailable =>
      'L’appareil photo n’est pas disponible. Vérifiez l’autorisation dans les réglages du téléphone.';

  @override
  String get cancel => 'Annuler';

  @override
  String get cancelReason => 'Motif d’annulation';

  @override
  String get cancelReasonHint => 'Pourquoi l’annuler ?';

  @override
  String get cancelRequest => 'Annuler la demande';

  @override
  String get cancelRestock => 'Annuler le réassort';

  @override
  String get cancelRule => 'Annuler cette valeur';

  @override
  String get cancelRuleBody =>
      'Les ventes déjà faites gardent leur gain. Les ventes à venir ne le gagneront plus.';

  @override
  String get cancelRuleTitle => 'Annuler cette valeur ?';

  @override
  String get cancelSale => 'Annuler la vente';

  @override
  String get cancelSaleBody =>
      'Le stock est remis et le gain est retiré de votre portefeuille.';

  @override
  String get cancelSaleTitle => 'Annuler cette vente ?';

  @override
  String get catalogTitle => 'Catalogue';

  @override
  String celebrateSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unités vendues',
      one: '1 unité vendue',
    );
    return '$_temp0';
  }

  @override
  String get celebrateTitle => 'Belle vente !';

  @override
  String get celebrateToday => 'Aujourd’hui jusqu’ici';

  @override
  String get changePassword => 'Changer le mot de passe';

  @override
  String get changeReceiver => 'Changer qui compte la marchandise';

  @override
  String get chooseAudience => 'Choisissez qui la reçoit';

  @override
  String get chooseGrossiste => 'Choisir un grossiste';

  @override
  String get choosePdvs => 'Choisir des points de vente';

  @override
  String get chooseProduct => 'Choisir un produit';

  @override
  String get chooseReceiver => 'Choisir qui compte la marchandise';

  @override
  String get city => 'Ville';

  @override
  String get close => 'Fermer';

  @override
  String get codeInvalid => 'Saisissez un code valide.';

  @override
  String get colApproved => 'Validé';

  @override
  String get colReceived => 'Compté';

  @override
  String get colRequested => 'Demandé';

  @override
  String get colShipped => 'Envoyé';

  @override
  String get completed => 'Terminé';

  @override
  String get confirm => 'Confirmer';

  @override
  String get confirmDelivery => 'Confirmer la livraison';

  @override
  String get confirmPassword => 'Confirmer le mot de passe';

  @override
  String get correctSale => 'Corriger cette vente';

  @override
  String get correctSaleHint =>
      'Modifiez les quantités. Mettez un produit à 0 pour le retirer, ou tout à 0 pour annuler la vente.';

  @override
  String get corrected => 'Corrigée';

  @override
  String get correctionWindowClosed =>
      'Une vente se corrige pendant 48 heures. Demandez à votre responsable pour les corrections plus tardives.';

  @override
  String get corrections => 'Corrections';

  @override
  String get countedProducts => 'Produits comptés';

  @override
  String get counting => 'Calcul…';

  @override
  String get courseAudienceHint =>
      'Laissez vide pour la montrer à tout le monde.';

  @override
  String get courseDeleted => 'Formation supprimée';

  @override
  String get courseIsDraft => 'Formation dépubliée';

  @override
  String get courseIsPublished => 'Formation publiée';

  @override
  String get courseSummary => 'Courte description';

  @override
  String get courseTitle => 'Titre de la formation';

  @override
  String get create => 'Créer';

  @override
  String get createAndInvite => 'Créer et envoyer l’invitation';

  @override
  String get createPdv => 'Créer le point de vente';

  @override
  String get current => 'En cours';

  @override
  String get currentPassword => 'Mot de passe actuel';

  @override
  String get customPeriod => 'Choisir des dates';

  @override
  String get date => 'Date';

  @override
  String dateRange(String from, String to) {
    return '$from → $to';
  }

  @override
  String get deactivate => 'Désactiver';

  @override
  String get deactivateBody =>
      'La personne sera déconnectée et n’aura plus accès.';

  @override
  String deactivateTitle(String name) {
    return 'Désactiver $name ?';
  }

  @override
  String get deactivated => 'Désactivé';

  @override
  String get decision => 'Décision';

  @override
  String get declaration => 'Déclaration de stock';

  @override
  String get declarationRejectedRetry =>
      'Votre dernière déclaration de stock a été refusée. Déclarez-la à nouveau.';

  @override
  String get declarationSent => 'Envoyé à BioBalance pour approbation';

  @override
  String get declarationWaiting =>
      'Une déclaration de stock attend son approbation.';

  @override
  String get declarations => 'Déclarations';

  @override
  String get declareFirstHint =>
      'Comptez chaque produit, saisissez les quantités et prenez une photo du stock. BioBalance le vérifie, puis le stock devient officiel.';

  @override
  String get declareStock => 'Déclarer le stock';

  @override
  String declaredQuantity(int count) {
    return 'Déclaré : $count';
  }

  @override
  String get decline => 'Refuser';

  @override
  String get declinePayoutTitle => 'Pourquoi refuser ce paiement ?';

  @override
  String get decrease => 'Diminuer';

  @override
  String get delete => 'Supprimer';

  @override
  String get deleteCourse => 'Supprimer la formation';

  @override
  String get deleteCourseBody =>
      'Ses leçons et la progression de chacun sont supprimées.';

  @override
  String get deleteCourseTitle => 'Supprimer cette formation ?';

  @override
  String get deleteLessonTitle => 'Supprimer cette leçon ?';

  @override
  String get deliverTo => 'Livrer à';

  @override
  String deliveriesToConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count livraisons à confirmer',
      one: '1 livraison à confirmer',
    );
    return '$_temp0';
  }

  @override
  String get deliveriesToConfirmHint =>
      'Photographiez le bon et comptez la marchandise.';

  @override
  String get deliveryPaper => 'Bon de livraison';

  @override
  String get deliverySent => 'Envoyé à BioBalance pour approbation';

  @override
  String get depotName => 'Nom du dépôt';

  @override
  String get description => 'Description';

  @override
  String get discard => 'Abandonner';

  @override
  String get done => 'Terminé';

  @override
  String get draft => 'Brouillon';

  @override
  String get durationMinutes => 'Minutes';

  @override
  String get earnedToday => 'Gagné aujourd’hui';

  @override
  String get edit => 'Modifier';

  @override
  String get editCourse => 'Modifier la formation';

  @override
  String get editLesson => 'Modifier la leçon';

  @override
  String get editPdv => 'Modifier le point de vente';

  @override
  String get editProduct => 'Modifier le produit';

  @override
  String get editProfile => 'Modifier mon profil';

  @override
  String get email => 'E-mail';

  @override
  String get emailInvalid => 'Saisissez une adresse e-mail valide.';

  @override
  String endsOn(String date) {
    return 'Fin : $date';
  }

  @override
  String get entryCorrection => 'Correction';

  @override
  String get entryPayout => 'Paiement';

  @override
  String get entrySale => 'Gain d’une vente';

  @override
  String get errorGeneric => 'Une erreur est survenue. Veuillez réessayer.';

  @override
  String get errorOffline =>
      'Pas de connexion. Vérifiez votre accès internet et réessayez.';

  @override
  String get errorServer =>
      'Le service est momentanément indisponible. Réessayez bientôt.';

  @override
  String get everyone => 'Tout le monde';

  @override
  String get exportCsv => 'Exporter vers un tableur';

  @override
  String get family => 'Famille';

  @override
  String get familyHint => 'Les récompenses peuvent être fixées par famille.';

  @override
  String get fieldRequired => 'Obligatoire';

  @override
  String get fileAttached => 'Fichier joint';

  @override
  String get filterDone => 'Terminés';

  @override
  String get filterOpen => 'En cours';

  @override
  String get forgotCodeSubtitle =>
      'Saisissez le code reçu par e-mail et votre nouveau mot de passe.';

  @override
  String get forgotPassword => 'Mot de passe oublié ?';

  @override
  String get forgotSubtitle =>
      'Nous vous envoyons un code par e-mail, valable 30 minutes.';

  @override
  String get forgotTitle => 'Réinitialiser le mot de passe';

  @override
  String fromDate(String date) {
    return 'À partir du $date';
  }

  @override
  String get fullName => 'Nom complet';

  @override
  String get fullNameOptional => 'Votre nom (facultatif)';

  @override
  String get grossisteDeclareFirst =>
      'Déclarez le stock de votre dépôt avec une photo pour que BioBalance l’approuve.';

  @override
  String get group => 'Groupe';

  @override
  String get groupCreated => 'Groupe créé. Il attend son approbation.';

  @override
  String get groupName => 'Nom du groupe';

  @override
  String get groupedBy => 'Par';

  @override
  String get haveCode => 'J’ai déjà un code';

  @override
  String helloName(String name) {
    return 'Bonjour, $name';
  }

  @override
  String get history => 'Historique';

  @override
  String get howToUse => 'Conseils d’utilisation';

  @override
  String get inRegions => 'Dans ces régions';

  @override
  String get inactive => 'Inactif';

  @override
  String get increase => 'Augmenter';

  @override
  String get ingredients => 'Ingrédients';

  @override
  String get initialStock => 'Stock de départ';

  @override
  String get invitationResent => 'Invitation renvoyée';

  @override
  String get invitationSent => 'Invitation envoyée';

  @override
  String get invitedHint =>
      'Votre compte est approuvé et vous avez reçu un code par e-mail ?';

  @override
  String get kind => 'Type';

  @override
  String get language => 'Langue';

  @override
  String get last7Days => '7 derniers jours';

  @override
  String get lastMonth => 'Mois dernier';

  @override
  String get latestSales => 'Dernières ventes';

  @override
  String get lessonArticle => 'Lecture';

  @override
  String get lessonPdf => 'Document';

  @override
  String get lessonText => 'Texte de la leçon';

  @override
  String get lessonTitle => 'Titre de la leçon';

  @override
  String get lessonVideo => 'Vidéo';

  @override
  String get lessons => 'Leçons';

  @override
  String lessonsDone(int done, int total) {
    return '$done leçons sur $total';
  }

  @override
  String get lowStock => 'Produits presque épuisés';

  @override
  String get manageTraining => 'Gérer les formations';

  @override
  String get markAllRead => 'Tout marquer lu';

  @override
  String get markAsPaid => 'Marquer comme payé';

  @override
  String markAsPaidHint(String amount) {
    return 'Confirmez que vous avez payé $amount. Le montant quitte leur portefeuille.';
  }

  @override
  String get markDone => 'Marquer comme terminé';

  @override
  String get markNotDone => 'Marquer comme non terminé';

  @override
  String get markShipped => 'Marquer comme expédié';

  @override
  String get me => 'Moi';

  @override
  String get memberAdded => 'Membre ajouté. En attente d’approbation.';

  @override
  String get message => 'Message';

  @override
  String minutes(int count) {
    return '$count min';
  }

  @override
  String get more => 'Plus';

  @override
  String get moreTitle => 'Plus';

  @override
  String myRegion(String name) {
    return 'Région $name';
  }

  @override
  String myRestockRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de vos demandes de réassort sont en cours',
      one: '1 de vos demandes de réassort est en cours',
      zero: 'Aucune demande de réassort en cours',
    );
    return '$_temp0';
  }

  @override
  String get needsAttention => 'À surveiller';

  @override
  String get negativeStock => 'Produits sous zéro';

  @override
  String get networkTitle => 'Réseau';

  @override
  String get newAccount => 'Nouveau compte';

  @override
  String get newAccountHint =>
      'La personne reçoit un e-mail avec un code pour choisir son mot de passe.';

  @override
  String get newAnnouncement => 'Nouvelle annonce';

  @override
  String get newCourse => 'Nouvelle formation';

  @override
  String get newGroup => 'Nouveau groupe';

  @override
  String get newPassword => 'Nouveau mot de passe';

  @override
  String get newPdv => 'Nouveau point de vente';

  @override
  String get newPdvHint =>
      'Il peut être configuré tout de suite. BioBalance l’approuve avant qu’il vende.';

  @override
  String get newProduct => 'Nouveau produit';

  @override
  String get newSale => 'Nouvelle vente';

  @override
  String get next => 'Suivant';

  @override
  String get noActivePdv =>
      'Il faut un point de vente approuvé pour demander un réassort.';

  @override
  String get noActivityYet => 'Aucune activité pour l’instant';

  @override
  String get noAnnouncements => 'Aucune annonce pour l’instant';

  @override
  String get noAnnouncementsHint =>
      'Écrivez aux responsables, grossistes ou équipes.';

  @override
  String get noCourses => 'Aucune formation pour l’instant';

  @override
  String get noCoursesAdminHint =>
      'Créez une formation, ajoutez des leçons, puis publiez-la.';

  @override
  String get noCoursesHint => 'Les nouvelles formations apparaîtront ici.';

  @override
  String get noEndDate => 'Sans date de fin';

  @override
  String get noGrossisteYet =>
      'Aucun grossiste pour l’instant. Créez d’abord un compte.';

  @override
  String get noGroup => 'Aucun groupe';

  @override
  String get noGroups => 'Aucun groupe pour l’instant';

  @override
  String get noGroupsHint =>
      'Un groupe réunit plusieurs points de vente d’un même propriétaire.';

  @override
  String get noHistoryYet => 'Rien d’enregistré pour l’instant';

  @override
  String get noLessonsYet =>
      'Aucune leçon. Ajoutez-en une pour publier la formation.';

  @override
  String get noNotifications => 'Rien de nouveau';

  @override
  String get noNotificationsHint =>
      'Les annonces et mises à jour apparaîtront ici.';

  @override
  String get noOrdersToPrepare => 'Aucune commande à préparer';

  @override
  String get noPayoutRequests => 'Aucune demande de paiement';

  @override
  String get noPayoutsYet => 'Aucun paiement pour l’instant';

  @override
  String get noPdvs => 'Aucun point de vente pour l’instant';

  @override
  String get noPdvsHint =>
      'Ajoutez votre premier point de vente avec le bouton ci-dessous.';

  @override
  String get noPeople => 'Personne pour l’instant';

  @override
  String get noProductsFound => 'Aucun produit trouvé';

  @override
  String get noRestocks => 'Aucun réassort';

  @override
  String get noRestocksHint =>
      'Demandez des produits pour un point de vente lorsqu’il en manque.';

  @override
  String get noRewardsYet => 'Aucune récompense fixée';

  @override
  String get noRewardsYetHint =>
      'Choisissez une famille ou un produit et un montant par unité vendue.';

  @override
  String get noRulesHere => 'Rien ici';

  @override
  String get noSalesInPeriod => 'Aucune vente sur cette période';

  @override
  String get noSalesYet => 'Aucune vente pour l’instant';

  @override
  String get noSalesYetHint =>
      'Vos ventes et ce qu’elles ont rapporté apparaîtront ici.';

  @override
  String get noStockYet => 'Pas encore de stock';

  @override
  String get noStockYetHint =>
      'Comptez ce que vous avez, prenez une photo et envoyez-la à BioBalance.';

  @override
  String get noTeamYet => 'Aucun membre d’équipe pour l’instant.';

  @override
  String get noWalletsYet => 'Aucun portefeuille pour l’instant';

  @override
  String get none => 'Aucun';

  @override
  String get notReadYet => 'Pas encore lu';

  @override
  String get note => 'Note';

  @override
  String get nothingToApprove => 'Rien à valider';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get openDocument => 'Ouvrir le document';

  @override
  String get openRestocks => 'Réassorts en cours';

  @override
  String get openVideo => 'Voir la vidéo';

  @override
  String get optional => 'facultatif';

  @override
  String get orVideoLink => 'Ou un lien vidéo';

  @override
  String get ordersTitle => 'Commandes';

  @override
  String ordersToPrepare(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count commandes à préparer',
      one: '1 commande à préparer',
    );
    return '$_temp0';
  }

  @override
  String overlapBody(String details) {
    return 'Ces jours sont déjà couverts :\n$details\n\nLa remplacer par la nouvelle valeur ?';
  }

  @override
  String get overlapTitle => 'Une autre valeur s’applique déjà';

  @override
  String get packageSize => 'Contenance';

  @override
  String paidOn(String date) {
    return 'Payé le $date';
  }

  @override
  String get password => 'Mot de passe';

  @override
  String get passwordChanged =>
      'Mot de passe modifié. Vous pouvez vous connecter.';

  @override
  String get passwordChangedShort => 'Mot de passe modifié';

  @override
  String get passwordRequired => 'Saisissez votre mot de passe.';

  @override
  String get passwordRule => 'Au moins 10 caractères.';

  @override
  String get passwordTooShort => 'Utilisez au moins 10 caractères.';

  @override
  String get passwordsDiffer => 'Les mots de passe ne correspondent pas.';

  @override
  String get past => 'Passées';

  @override
  String get payoutApproved => 'Paiement enregistré';

  @override
  String get payoutExplain =>
      'L’administration vous paie puis confirme. Le montant quitte votre portefeuille une fois approuvé.';

  @override
  String get payoutPaid => 'Payé';

  @override
  String get payoutRequested => 'Paiement demandé';

  @override
  String get payoutRequests => 'Demandes de paiement';

  @override
  String get payouts => 'Paiements';

  @override
  String get payoutsTitle => 'Paiements';

  @override
  String get paysToday => 'Valeurs du jour';

  @override
  String get paysTodayHint =>
      'Ce que rapporte une unité vendue aujourd’hui, produit par produit.';

  @override
  String pdvCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points de vente',
      one: '1 point de vente',
      zero: 'Aucun point de vente',
    );
    return '$_temp0';
  }

  @override
  String get pdvCreated => 'Point de vente créé. Il attend son approbation.';

  @override
  String get pdvName => 'Nom du point de vente';

  @override
  String get pdvNotActive =>
      'Votre point de vente attend son approbation. Vous pourrez vendre dès qu’il sera actif.';

  @override
  String get pdvWaitingNotice =>
      'En attente d’approbation par BioBalance. Vous pouvez déjà ajouter l’équipe et déclarer le stock.';

  @override
  String pdvsChosen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points de vente choisis',
      one: '1 point de vente choisi',
    );
    return '$_temp0';
  }

  @override
  String pendingCount(int count) {
    return '$count en attente';
  }

  @override
  String pendingPayout(String amount) {
    return '$amount déjà demandé';
  }

  @override
  String get people => 'Personnes';

  @override
  String get perUnit => 'par unité';

  @override
  String get periods => 'Périodes';

  @override
  String get phone => 'Téléphone';

  @override
  String get photo => 'Photo';

  @override
  String get photoChoose => 'Choisir dans la galerie';

  @override
  String get photoHint => 'Touchez pour prendre une photo';

  @override
  String get photoOfPaper => 'Photo du bon de livraison';

  @override
  String get photoOfStock => 'Photo du stock';

  @override
  String get photoReady => 'Photo prête';

  @override
  String get photoRequiredHint => 'Prenez la photo pour envoyer.';

  @override
  String get photoRetake => 'Reprendre';

  @override
  String get photoTake => 'Prendre une photo';

  @override
  String get photoUploading => 'Envoi en cours…';

  @override
  String get pinAnnouncement => 'Épingler en haut';

  @override
  String get pinAnnouncementHint =>
      'Elle reste en haut de leurs notifications.';

  @override
  String get pinned => 'Épinglées';

  @override
  String get pointOfSale => 'Point de vente';

  @override
  String get precautions => 'Précautions';

  @override
  String get prepareAndShip => 'Préparer et expédier';

  @override
  String get productActive => 'Disponible';

  @override
  String get productActiveHint =>
      'Masqué des ventes et des commandes si désactivé.';

  @override
  String get productName => 'Nom du produit';

  @override
  String get productPhoto => 'Photo du produit';

  @override
  String get products => 'Produits';

  @override
  String get productsNeeded => 'Produits demandés';

  @override
  String get progress => 'Progression';

  @override
  String get progressByPerson => 'Progression par personne';

  @override
  String get publish => 'Publier';

  @override
  String get published => 'Publié';

  @override
  String get quantitiesAdjusted => 'Quantités ajustées';

  @override
  String get quantitiesReceived => 'Quantités reçues';

  @override
  String get quantity => 'Quantité';

  @override
  String quantityMax(int max) {
    return 'Jusqu’à $max';
  }

  @override
  String get reactivate => 'Réactiver';

  @override
  String get reactivated => 'Réactivé';

  @override
  String readAt(String date) {
    return 'Lu $date';
  }

  @override
  String readOf(int read, int total) {
    return '$read lu(s) sur $total';
  }

  @override
  String get reasonRequired => 'Motif (obligatoire)';

  @override
  String get receiveHint =>
      'Photographiez le bon de livraison signé et saisissez ce que vous avez réellement reçu pour chaque produit.';

  @override
  String get receivedBy => 'Compté par';

  @override
  String get receiverSaved => 'Enregistré';

  @override
  String get recent => 'Récentes';

  @override
  String get recipients => 'Destinataires';

  @override
  String get recordSale => 'Enregistrer la vente';

  @override
  String get recount => 'Recomptage';

  @override
  String get recountAsked => 'Renvoyé pour un nouveau comptage';

  @override
  String get recountHint =>
      'Les quantités ci-dessous sont celles du système. Corrigez-les selon votre comptage, ajoutez une photo et envoyez.';

  @override
  String get recountReasonHint => 'Qu’est-ce qui ne correspond pas au bon ?';

  @override
  String get recountStock => 'Recompter le stock';

  @override
  String get recoveryCode => 'Code de récupération';

  @override
  String get reference => 'Référence';

  @override
  String get refresh => 'Actualiser';

  @override
  String get region => 'Région';

  @override
  String regionOf(String name) {
    return 'Région $name';
  }

  @override
  String get regions => 'Régions';

  @override
  String get reject => 'Refuser';

  @override
  String get rejectReasonHint =>
      'Expliquez ce qu’il faut corriger pour pouvoir le renvoyer.';

  @override
  String get rejectReasonTitle => 'Pourquoi ce refus ?';

  @override
  String get rejected => 'Refusé';

  @override
  String get remove => 'Retirer';

  @override
  String get replaceValue => 'Remplacer';

  @override
  String get reportsTitle => 'Rapports';

  @override
  String get requestPayout => 'Demander un paiement';

  @override
  String get requestRestock => 'Demander un réassort';

  @override
  String get requestedBy => 'Demandé par';

  @override
  String requestedInStock(int requested, int stock) {
    return 'Demandé $requested · en stock $stock';
  }

  @override
  String requestedQuantity(int count) {
    return 'Demandé : $count';
  }

  @override
  String get resendInvitation => 'Renvoyer l’invitation';

  @override
  String get resetCodeSent => 'Si le compte existe, un code a été envoyé.';

  @override
  String get restock => 'Réassort';

  @override
  String get restockApproved => 'Réassort approuvé. Le stock est mis à jour.';

  @override
  String get restockAssigned => 'Chez le grossiste';

  @override
  String get restockCancelled => 'Réassort annulé';

  @override
  String get restockCompleted => 'Terminé';

  @override
  String get restockReceived => 'À valider';

  @override
  String get restockRequested => 'Demandé';

  @override
  String get restockRouted => 'La commande a été transmise';

  @override
  String get restockSent => 'Demande envoyée';

  @override
  String get restockShipped => 'En route';

  @override
  String get restockShippedMessage => 'Marqué comme expédié';

  @override
  String get restocksTitle => 'Réassorts';

  @override
  String get resubmit => 'Soumettre à nouveau';

  @override
  String get resubmitted => 'Soumis à nouveau';

  @override
  String get retry => 'Réessayer';

  @override
  String reviewSale(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Vérifier la vente · $count unités',
      one: 'Vérifier la vente · 1 unité',
    );
    return '$_temp0';
  }

  @override
  String get reviewTitle => 'Vérifier la vente';

  @override
  String get reward => 'Gain';

  @override
  String get rewardSaved => 'Récompense enregistrée';

  @override
  String get rewardsMonth => 'Gains, 30 jours';

  @override
  String get rewardsTitle => 'Récompenses';

  @override
  String get roleAdmin => 'Administrateur';

  @override
  String get roleGrossiste => 'Grossiste';

  @override
  String get roleGrossistePlural => 'Grossistes';

  @override
  String get roleResponsable => 'Responsable';

  @override
  String get roleResponsablePlural => 'Responsables';

  @override
  String get roleVendeur => 'Membre de l’équipe';

  @override
  String get roleVendeurPlural => 'Membres d’équipe';

  @override
  String get roleVendeurShort => 'Membre';

  @override
  String get ruleCancelled => 'Valeur annulée';

  @override
  String get saleCancelled => 'Vente annulée';

  @override
  String get saleCorrected => 'Vente corrigée';

  @override
  String get saleDetailTitle => 'Vente';

  @override
  String get saleRecordedTitle => 'Vente enregistrée';

  @override
  String get saleRefused => 'Le serveur a refusé cette vente';

  @override
  String get saleVoided => 'Annulée';

  @override
  String salesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ventes',
      one: '1 vente',
      zero: 'Aucune vente',
    );
    return '$_temp0';
  }

  @override
  String get salesLast14Days => 'Unités vendues, 14 derniers jours';

  @override
  String get salesTitle => 'Mes ventes';

  @override
  String get salesTitleShort => 'Ventes';

  @override
  String salesWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ventes attendent d’être envoyées',
      one: '1 vente attend d’être envoyée',
    );
    return '$_temp0';
  }

  @override
  String get save => 'Enregistrer';

  @override
  String get saveCorrection => 'Enregistrer la correction';

  @override
  String get saveReward => 'Enregistrer la récompense';

  @override
  String get saved => 'Enregistré';

  @override
  String savedOnPhoneBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unités seront envoyées',
      one: '1 unité sera envoyée',
    );
    return '$_temp0 dès que vous serez de nouveau connecté. Votre gain apparaîtra alors.';
  }

  @override
  String get savedOnPhoneTitle => 'Enregistrée sur votre téléphone';

  @override
  String get scanHint => 'Visez le code-barres avec l’appareil photo';

  @override
  String get scanTitle => 'Scanner un produit';

  @override
  String get schedule => 'Planifier';

  @override
  String get scheduleTitle => 'Planifier cette annonce ?';

  @override
  String get scheduled => 'Planifiée';

  @override
  String scheduledFor(String date) {
    return 'Prévue le $date';
  }

  @override
  String get search => 'Rechercher';

  @override
  String get searchProducts => 'Rechercher un produit';

  @override
  String get seeAll => 'Tout voir';

  @override
  String get seller => 'Vendeur';

  @override
  String get send => 'Envoyer';

  @override
  String get sendCode => 'Envoyer un code';

  @override
  String get sendForApproval => 'Envoyer pour approbation';

  @override
  String get sendFromBiobalance => 'Envoyer depuis BioBalance';

  @override
  String get sendNow => 'Envoyer';

  @override
  String get sendNowOption => 'Envoyer maintenant';

  @override
  String sendNowTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personnes',
      one: '1 personne',
    );
    return 'Envoyer à $_temp0 ?';
  }

  @override
  String get sendRequest => 'Envoyer la demande';

  @override
  String get sendToAdmin => 'Envoyer à BioBalance';

  @override
  String get sentBy => 'Envoyé par';

  @override
  String get sentFrom => 'Envoyé par';

  @override
  String get server => 'Serveur';

  @override
  String get setReward => 'Fixer une récompense';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String shipHint(String destination) {
    return 'Saisissez ce qui part de votre dépôt vers $destination.';
  }

  @override
  String shippedReceived(int shipped, int received) {
    return 'Envoyé $shipped · compté $received';
  }

  @override
  String get signIn => 'Se connecter';

  @override
  String get signInSubtitle => 'Connectez-vous à votre compte BioBalance.';

  @override
  String get signInTitle => 'Bon retour';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get signOutTitle => 'Se déconnecter de BioBalance ?';

  @override
  String startsOn(String date) {
    return 'Début : $date';
  }

  @override
  String get statusActive => 'Actif';

  @override
  String get statusApproved => 'Approuvé';

  @override
  String get statusCancelled => 'Annulé';

  @override
  String get statusPending => 'En attente';

  @override
  String get statusRejected => 'Refusé';

  @override
  String get statusSuspended => 'Suspendu';

  @override
  String get statusWaitingApproval => 'En attente d’approbation';

  @override
  String get stockAllGood => 'Tous les stocks sont corrects';

  @override
  String get stockApproved => 'Stock approuvé';

  @override
  String get stockApprovedLong => 'Stock approuvé : voir les quantités';

  @override
  String get stockLevels => 'Quantités';

  @override
  String get stockLow => 'Faible';

  @override
  String get stockMissing => 'Pas encore de stock';

  @override
  String get stockMissingLong => 'Déclarez le stock de départ avec une photo';

  @override
  String get stockNegative => 'Sous zéro';

  @override
  String get stockRejected => 'Stock refusé';

  @override
  String get stockRejectedLong => 'Stock refusé : à déclarer à nouveau';

  @override
  String get stockTitle => 'Stock';

  @override
  String get stockWaiting => 'Stock en attente';

  @override
  String get stockWaitingLong => 'Stock en attente d’approbation';

  @override
  String get suspend => 'Suspendre';

  @override
  String get suspendPdvBody =>
      'Son équipe ne pourra plus vendre jusqu’à sa réactivation.';

  @override
  String suspendTitle(String name) {
    return 'Suspendre $name ?';
  }

  @override
  String get suspended => 'Suspendu';

  @override
  String get system => 'Système';

  @override
  String get tabApprovals => 'Validations';

  @override
  String get tabGroups => 'Groupes';

  @override
  String get tabHome => 'Accueil';

  @override
  String get tabLearn => 'Formation';

  @override
  String get tabNetwork => 'Réseau';

  @override
  String get tabOrders => 'Commandes';

  @override
  String get tabPdvs => 'Magasins';

  @override
  String get tabPeople => 'Personnes';

  @override
  String get tabReports => 'Rapports';

  @override
  String get tabRestocks => 'Réassorts';

  @override
  String get tabSales => 'Ventes';

  @override
  String get tabWallet => 'Portefeuille';

  @override
  String get team => 'Équipe';

  @override
  String teamCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membres',
      one: '1 membre',
      zero: 'Aucune équipe',
    );
    return '$_temp0';
  }

  @override
  String get thisMonth => 'Ce mois-ci';

  @override
  String get thisWeek => 'Cette semaine';

  @override
  String get title => 'Titre';

  @override
  String get toPay => 'À payer';

  @override
  String get today => 'Aujourd’hui';

  @override
  String get topPdvs => 'Meilleurs points de vente, 30 jours';

  @override
  String get topProducts => 'Produits phares, 30 jours';

  @override
  String get torch => 'Lampe';

  @override
  String get totalUnits => 'Total d’unités';

  @override
  String get trainingTitle => 'Formation';

  @override
  String trendSemantics(int total) {
    return 'Graphique : $total unités vendues sur les 14 derniers jours';
  }

  @override
  String get typeGroup => 'Groupe';

  @override
  String get typeMember => 'Membre d’équipe';

  @override
  String get typePayout => 'Paiement';

  @override
  String get typePdv => 'Point de vente';

  @override
  String get typeReceipt => 'Livraison';

  @override
  String get typeRestockRequest => 'Demande de réassort';

  @override
  String get typeStock => 'Stock';

  @override
  String units(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unités',
      one: '1 unité',
    );
    return '$_temp0';
  }

  @override
  String get unpublish => 'Dépublier';

  @override
  String get upcoming => 'À venir';

  @override
  String get uploadPdf => 'Téléverser un PDF';

  @override
  String get uploadVideo => 'Téléverser une vidéo (MP4)';

  @override
  String get videoUnavailable => 'Cette vidéo ne peut pas être lue.';

  @override
  String get viewSales => 'Voir les ventes';

  @override
  String waitingAdmin(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments attendent l’approbation de BioBalance',
      one: '1 élément attend l’approbation de BioBalance',
    );
    return '$_temp0';
  }

  @override
  String waitingForYou(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments vous attendent',
      one: '1 élément vous attend',
    );
    return '$_temp0';
  }

  @override
  String get waitingToSend => 'En attente d’envoi';

  @override
  String get walletBalance => 'Solde du portefeuille';

  @override
  String walletSummaryLine(String earned, String paid) {
    return 'Gagné $earned · payé $paid';
  }

  @override
  String get walletTitle => 'Portefeuille';

  @override
  String get wallets => 'Portefeuilles';

  @override
  String get whoCountsHint =>
      'Cette personne photographiera le bon et saisira les quantités.';

  @override
  String get whoCountsTheGoods => 'Qui compte la marchandise ?';

  @override
  String get whoIsItFor => 'À qui s’adresse-t-elle ?';

  @override
  String get wholeNetwork => 'Tout le réseau';

  @override
  String willReach(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personnes la recevront',
      one: '1 personne la recevra',
      zero: 'Personne ne la recevrait',
    );
    return '$_temp0';
  }

  @override
  String get withdrawAnnouncement => 'Retirer l’annonce';

  @override
  String get withdrawBody =>
      'Elle n’a pas encore été envoyée et ne partira pas.';

  @override
  String get withdrawTitle => 'Retirer cette annonce ?';

  @override
  String get withdrawn => 'Annonce retirée';

  @override
  String get yesterday => 'Hier';

  @override
  String get youEarned => 'Vous avez gagné';
}
