// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get about => 'About';

  @override
  String get account => 'Account';

  @override
  String get accountActivated => 'Account activated. You can sign in.';

  @override
  String get activateAccount => 'Activate my account';

  @override
  String get activateSubtitle =>
      'Enter the email and the code you received, then choose a password.';

  @override
  String get activateTitle => 'Activate your account';

  @override
  String get activationCode => 'Activation code';

  @override
  String get activity => 'Activity';

  @override
  String get add => 'Add';

  @override
  String get addProduct => 'Add a product';

  @override
  String addSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Add $count products',
      one: 'Add 1 product',
      zero: 'Choose products',
    );
    return '$_temp0';
  }

  @override
  String addToSale(String name) {
    return 'Add $name';
  }

  @override
  String addedToSale(String name) {
    return '$name added';
  }

  @override
  String get all => 'All';

  @override
  String get amountTnd => 'Amount';

  @override
  String get appName => 'BioBalance';

  @override
  String get appVersion => 'Version';

  @override
  String get authenticatorCode => 'Authenticator code';

  @override
  String get authenticatorCodeHelp =>
      'The 6 digits from your authenticator app.';

  @override
  String get availableBalance => 'Available balance';

  @override
  String availableUpTo(String amount) {
    return 'Up to $amount';
  }

  @override
  String get back => 'Back';

  @override
  String get barcodeUnknown => 'This barcode is not in the catalog.';

  @override
  String get cameraUnavailable =>
      'The camera is not available. Check the permission in your phone settings.';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelRequest => 'Cancel request';

  @override
  String get cancelSale => 'Cancel the sale';

  @override
  String get cancelSaleBody =>
      'The stock is put back and the reward is taken off your wallet.';

  @override
  String get cancelSaleTitle => 'Cancel this sale?';

  @override
  String celebrateSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count units sold',
      one: '1 unit sold',
    );
    return '$_temp0';
  }

  @override
  String get celebrateTitle => 'Great sale!';

  @override
  String get celebrateToday => 'Today so far';

  @override
  String get changePassword => 'Change password';

  @override
  String get close => 'Close';

  @override
  String get codeInvalid => 'Enter a valid code.';

  @override
  String get completed => 'Completed';

  @override
  String get confirm => 'Confirm';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get correctSale => 'Correct this sale';

  @override
  String get correctSaleHint =>
      'Change the quantities. Set a product to 0 to remove it, or all to 0 to cancel the sale.';

  @override
  String get corrected => 'Corrected';

  @override
  String get correctionWindowClosed =>
      'A sale can be corrected for 48 hours. Ask your responsable for later corrections.';

  @override
  String get corrections => 'Corrections';

  @override
  String get create => 'Create';

  @override
  String get currentPassword => 'Current password';

  @override
  String get decrease => 'Decrease';

  @override
  String get delete => 'Delete';

  @override
  String get discard => 'Discard';

  @override
  String get done => 'Done';

  @override
  String get draft => 'Draft';

  @override
  String get earnedToday => 'Earned today';

  @override
  String get edit => 'Edit';

  @override
  String get editProfile => 'Edit my profile';

  @override
  String get email => 'Email';

  @override
  String get emailInvalid => 'Enter a valid email address.';

  @override
  String get entryCorrection => 'Correction';

  @override
  String get entryPayout => 'Payout';

  @override
  String get entrySale => 'Sale reward';

  @override
  String get errorGeneric => 'Something went wrong. Please try again.';

  @override
  String get errorOffline =>
      'No connection. Check your internet and try again.';

  @override
  String get errorServer =>
      'The service is temporarily unavailable. Try again shortly.';

  @override
  String get forgotCodeSubtitle =>
      'Enter the code from the email and your new password.';

  @override
  String get forgotPassword => 'Forgot your password?';

  @override
  String get forgotSubtitle =>
      'We will email you a code, valid for 30 minutes.';

  @override
  String get forgotTitle => 'Reset your password';

  @override
  String get fullName => 'Full name';

  @override
  String get fullNameOptional => 'Your name (optional)';

  @override
  String get haveCode => 'I already have a code';

  @override
  String helloName(String name) {
    return 'Hello, $name';
  }

  @override
  String get increase => 'Increase';

  @override
  String get invitedHint =>
      'Your account was approved and you received a code by email?';

  @override
  String get language => 'Language';

  @override
  String get latestSales => 'Latest sales';

  @override
  String get lessonArticle => 'Reading';

  @override
  String get lessonPdf => 'Document';

  @override
  String get lessonVideo => 'Video';

  @override
  String lessonsDone(int done, int total) {
    return '$done of $total lessons';
  }

  @override
  String get manageTraining => 'Manage courses';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get markDone => 'Mark as done';

  @override
  String get markNotDone => 'Mark as not done';

  @override
  String minutes(int count) {
    return '$count min';
  }

  @override
  String get more => 'More';

  @override
  String get moreTitle => 'More';

  @override
  String get newPassword => 'New password';

  @override
  String get newSale => 'New sale';

  @override
  String get next => 'Next';

  @override
  String get noActivityYet => 'No activity yet';

  @override
  String get noCourses => 'No course yet';

  @override
  String get noCoursesHint => 'New courses will appear here.';

  @override
  String get noNotifications => 'Nothing new';

  @override
  String get noNotificationsHint =>
      'Announcements and updates will appear here.';

  @override
  String get noProductsFound => 'No product found';

  @override
  String get noSalesYet => 'No sales yet';

  @override
  String get noSalesYetHint =>
      'Your sales and what they earned will appear here.';

  @override
  String get none => 'None';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get openDocument => 'Open the document';

  @override
  String get openVideo => 'Watch the video';

  @override
  String get optional => 'optional';

  @override
  String get password => 'Password';

  @override
  String get passwordChanged => 'Password changed. You can sign in.';

  @override
  String get passwordChangedShort => 'Password changed';

  @override
  String get passwordRequired => 'Enter your password.';

  @override
  String get passwordRule => 'At least 10 characters.';

  @override
  String get passwordTooShort => 'Use at least 10 characters.';

  @override
  String get passwordsDiffer => 'The passwords do not match.';

  @override
  String get payoutExplain =>
      'The admin will pay you and confirm. The amount leaves your wallet once approved.';

  @override
  String get payoutPaid => 'Paid';

  @override
  String get payoutRequested => 'Payout requested';

  @override
  String get payouts => 'Payouts';

  @override
  String get pdvNotActive =>
      'Your point of sale is waiting for approval. You can sell as soon as it is active.';

  @override
  String pendingPayout(String amount) {
    return '$amount already requested';
  }

  @override
  String get phone => 'Phone';

  @override
  String get photoChoose => 'Choose from gallery';

  @override
  String get photoHint => 'Tap to take a photo';

  @override
  String get photoReady => 'Photo ready';

  @override
  String get photoRetake => 'Retake';

  @override
  String get photoTake => 'Take a photo';

  @override
  String get photoUploading => 'Sending…';

  @override
  String get pinned => 'Pinned';

  @override
  String get pointOfSale => 'Point of sale';

  @override
  String get products => 'Products';

  @override
  String get published => 'Published';

  @override
  String get quantity => 'Quantity';

  @override
  String quantityMax(int max) {
    return 'Up to $max';
  }

  @override
  String get reasonRequired => 'Reason (required)';

  @override
  String get recent => 'Recent';

  @override
  String get recordSale => 'Record the sale';

  @override
  String get recoveryCode => 'Recovery code';

  @override
  String get refresh => 'Refresh';

  @override
  String get remove => 'Remove';

  @override
  String get requestPayout => 'Request a payout';

  @override
  String get resetCodeSent => 'If the account exists, a code was sent.';

  @override
  String get retry => 'Try again';

  @override
  String reviewSale(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Review sale · $count units',
      one: 'Review sale · 1 unit',
    );
    return '$_temp0';
  }

  @override
  String get reviewTitle => 'Review the sale';

  @override
  String get reward => 'Reward';

  @override
  String get roleAdmin => 'Administrator';

  @override
  String get roleGrossiste => 'Grossiste';

  @override
  String get roleResponsable => 'Responsable';

  @override
  String get roleVendeur => 'Team member';

  @override
  String get saleCancelled => 'Sale cancelled';

  @override
  String get saleCorrected => 'Sale corrected';

  @override
  String get saleDetailTitle => 'Sale';

  @override
  String get saleRecordedTitle => 'Sale recorded';

  @override
  String get saleRefused => 'The server refused this sale';

  @override
  String get saleVoided => 'Cancelled';

  @override
  String salesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sales',
      one: '1 sale',
      zero: 'No sales',
    );
    return '$_temp0';
  }

  @override
  String get salesTitle => 'My sales';

  @override
  String salesWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sales are waiting to be sent',
      one: '1 sale is waiting to be sent',
    );
    return '$_temp0';
  }

  @override
  String get save => 'Save';

  @override
  String get saveCorrection => 'Save the correction';

  @override
  String get saved => 'Saved';

  @override
  String savedOnPhoneBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count units',
      one: '1 unit',
    );
    return '$_temp0 will be sent as soon as you are back online. Your reward will then appear.';
  }

  @override
  String get savedOnPhoneTitle => 'Saved on your phone';

  @override
  String get scanHint => 'Point the camera at the barcode';

  @override
  String get scanTitle => 'Scan a product';

  @override
  String get search => 'Search';

  @override
  String get searchProducts => 'Search a product';

  @override
  String get seeAll => 'See all';

  @override
  String get seller => 'Seller';

  @override
  String get send => 'Send';

  @override
  String get sendCode => 'Send me a code';

  @override
  String get sendNow => 'Send now';

  @override
  String get server => 'Server';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get signIn => 'Sign in';

  @override
  String get signInSubtitle => 'Sign in to your BioBalance account.';

  @override
  String get signInTitle => 'Welcome back';

  @override
  String get signOut => 'Sign out';

  @override
  String get signOutTitle => 'Sign out of BioBalance?';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get tabHome => 'Home';

  @override
  String get tabLearn => 'Learn';

  @override
  String get tabSales => 'Sales';

  @override
  String get tabWallet => 'Wallet';

  @override
  String get thisMonth => 'This month';

  @override
  String get thisWeek => 'This week';

  @override
  String get today => 'Today';

  @override
  String get torch => 'Flashlight';

  @override
  String get totalUnits => 'Total units';

  @override
  String get trainingTitle => 'Training';

  @override
  String units(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count units',
      one: '1 unit',
    );
    return '$_temp0';
  }

  @override
  String get videoUnavailable => 'This video cannot be played.';

  @override
  String get waitingToSend => 'Waiting to be sent';

  @override
  String get walletBalance => 'Wallet balance';

  @override
  String get walletTitle => 'Wallet';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get youEarned => 'You earned';
}
