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
  String get activateAccount => 'Activer mon compte';

  @override
  String get activateSubtitle =>
      'Saisissez l’e-mail et le code reçus, puis choisissez un mot de passe.';

  @override
  String get activateTitle => 'Activez votre compte';

  @override
  String get activationCode => 'Code d’activation';

  @override
  String get activity => 'Activité';

  @override
  String get add => 'Ajouter';

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
  String get all => 'Tous';

  @override
  String get amountTnd => 'Montant';

  @override
  String get appName => 'BioBalance';

  @override
  String get appVersion => 'Version';

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
  String get barcodeUnknown => 'Ce code-barres n’est pas dans le catalogue.';

  @override
  String get cameraUnavailable =>
      'L’appareil photo n’est pas disponible. Vérifiez l’autorisation dans les réglages du téléphone.';

  @override
  String get cancel => 'Annuler';

  @override
  String get cancelRequest => 'Annuler la demande';

  @override
  String get cancelSale => 'Annuler la vente';

  @override
  String get cancelSaleBody =>
      'Le stock est remis et le gain est retiré de votre portefeuille.';

  @override
  String get cancelSaleTitle => 'Annuler cette vente ?';

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
  String get close => 'Fermer';

  @override
  String get codeInvalid => 'Saisissez un code valide.';

  @override
  String get completed => 'Terminé';

  @override
  String get confirm => 'Confirmer';

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
  String get create => 'Créer';

  @override
  String get currentPassword => 'Mot de passe actuel';

  @override
  String get decrease => 'Diminuer';

  @override
  String get delete => 'Supprimer';

  @override
  String get discard => 'Abandonner';

  @override
  String get done => 'Terminé';

  @override
  String get draft => 'Brouillon';

  @override
  String get earnedToday => 'Gagné aujourd’hui';

  @override
  String get edit => 'Modifier';

  @override
  String get editProfile => 'Modifier mon profil';

  @override
  String get email => 'E-mail';

  @override
  String get emailInvalid => 'Saisissez une adresse e-mail valide.';

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
  String get fullName => 'Nom complet';

  @override
  String get fullNameOptional => 'Votre nom (facultatif)';

  @override
  String get haveCode => 'J’ai déjà un code';

  @override
  String helloName(String name) {
    return 'Bonjour, $name';
  }

  @override
  String get increase => 'Augmenter';

  @override
  String get invitedHint =>
      'Votre compte est approuvé et vous avez reçu un code par e-mail ?';

  @override
  String get language => 'Langue';

  @override
  String get latestSales => 'Dernières ventes';

  @override
  String get lessonArticle => 'Lecture';

  @override
  String get lessonPdf => 'Document';

  @override
  String get lessonVideo => 'Vidéo';

  @override
  String lessonsDone(int done, int total) {
    return '$done leçons sur $total';
  }

  @override
  String get manageTraining => 'Gérer les formations';

  @override
  String get markAllRead => 'Tout marquer lu';

  @override
  String get markDone => 'Marquer comme terminé';

  @override
  String get markNotDone => 'Marquer comme non terminé';

  @override
  String minutes(int count) {
    return '$count min';
  }

  @override
  String get more => 'Plus';

  @override
  String get moreTitle => 'Plus';

  @override
  String get newPassword => 'Nouveau mot de passe';

  @override
  String get newSale => 'Nouvelle vente';

  @override
  String get next => 'Suivant';

  @override
  String get noActivityYet => 'Aucune activité pour l’instant';

  @override
  String get noCourses => 'Aucune formation pour l’instant';

  @override
  String get noCoursesHint => 'Les nouvelles formations apparaîtront ici.';

  @override
  String get noNotifications => 'Rien de nouveau';

  @override
  String get noNotificationsHint =>
      'Les annonces et mises à jour apparaîtront ici.';

  @override
  String get noProductsFound => 'Aucun produit trouvé';

  @override
  String get noSalesYet => 'Aucune vente pour l’instant';

  @override
  String get noSalesYetHint =>
      'Vos ventes et ce qu’elles ont rapporté apparaîtront ici.';

  @override
  String get none => 'Aucun';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get openDocument => 'Ouvrir le document';

  @override
  String get openVideo => 'Voir la vidéo';

  @override
  String get optional => 'facultatif';

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
  String get payoutExplain =>
      'L’administration vous paie puis confirme. Le montant quitte votre portefeuille une fois approuvé.';

  @override
  String get payoutPaid => 'Payé';

  @override
  String get payoutRequested => 'Paiement demandé';

  @override
  String get payouts => 'Paiements';

  @override
  String get pdvNotActive =>
      'Votre point de vente attend son approbation. Vous pourrez vendre dès qu’il sera actif.';

  @override
  String pendingPayout(String amount) {
    return '$amount déjà demandé';
  }

  @override
  String get phone => 'Téléphone';

  @override
  String get photoChoose => 'Choisir dans la galerie';

  @override
  String get photoHint => 'Touchez pour prendre une photo';

  @override
  String get photoReady => 'Photo prête';

  @override
  String get photoRetake => 'Reprendre';

  @override
  String get photoTake => 'Prendre une photo';

  @override
  String get photoUploading => 'Envoi en cours…';

  @override
  String get pinned => 'Épinglées';

  @override
  String get pointOfSale => 'Point de vente';

  @override
  String get products => 'Produits';

  @override
  String get published => 'Publié';

  @override
  String get quantity => 'Quantité';

  @override
  String quantityMax(int max) {
    return 'Jusqu’à $max';
  }

  @override
  String get reasonRequired => 'Motif (obligatoire)';

  @override
  String get recent => 'Récentes';

  @override
  String get recordSale => 'Enregistrer la vente';

  @override
  String get recoveryCode => 'Code de récupération';

  @override
  String get refresh => 'Actualiser';

  @override
  String get remove => 'Retirer';

  @override
  String get requestPayout => 'Demander un paiement';

  @override
  String get resetCodeSent => 'Si le compte existe, un code a été envoyé.';

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
  String get roleAdmin => 'Administrateur';

  @override
  String get roleGrossiste => 'Grossiste';

  @override
  String get roleResponsable => 'Responsable';

  @override
  String get roleVendeur => 'Membre de l’équipe';

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
  String get salesTitle => 'Mes ventes';

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
  String get sendNow => 'Envoyer';

  @override
  String get server => 'Serveur';

  @override
  String get settingsTitle => 'Réglages';

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
  String get statusCancelled => 'Annulé';

  @override
  String get statusPending => 'En attente';

  @override
  String get statusRejected => 'Refusé';

  @override
  String get tabHome => 'Accueil';

  @override
  String get tabLearn => 'Formation';

  @override
  String get tabSales => 'Ventes';

  @override
  String get tabWallet => 'Portefeuille';

  @override
  String get thisMonth => 'Ce mois-ci';

  @override
  String get thisWeek => 'Cette semaine';

  @override
  String get today => 'Aujourd’hui';

  @override
  String get torch => 'Lampe';

  @override
  String get totalUnits => 'Total d’unités';

  @override
  String get trainingTitle => 'Formation';

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
  String get videoUnavailable => 'Cette vidéo ne peut pas être lue.';

  @override
  String get waitingToSend => 'En attente d’envoi';

  @override
  String get walletBalance => 'Solde du portefeuille';

  @override
  String get walletTitle => 'Portefeuille';

  @override
  String get yesterday => 'Hier';

  @override
  String get youEarned => 'Vous avez gagné';
}
