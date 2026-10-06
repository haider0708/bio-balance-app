import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @accountActivated.
  ///
  /// In en, this message translates to:
  /// **'Account activated. You can sign in.'**
  String get accountActivated;

  /// No description provided for @activateAccount.
  ///
  /// In en, this message translates to:
  /// **'Activate my account'**
  String get activateAccount;

  /// No description provided for @activateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the email and the code you received, then choose a password.'**
  String get activateSubtitle;

  /// No description provided for @activateTitle.
  ///
  /// In en, this message translates to:
  /// **'Activate your account'**
  String get activateTitle;

  /// No description provided for @activationCode.
  ///
  /// In en, this message translates to:
  /// **'Activation code'**
  String get activationCode;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add a product'**
  String get addProduct;

  /// No description provided for @addSelected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Choose products} =1{Add 1 product} other{Add {count} products}}'**
  String addSelected(int count);

  /// No description provided for @addToSale.
  ///
  /// In en, this message translates to:
  /// **'Add {name}'**
  String addToSale(String name);

  /// No description provided for @addedToSale.
  ///
  /// In en, this message translates to:
  /// **'{name} added'**
  String addedToSale(String name);

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @amountTnd.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountTnd;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'BioBalance'**
  String get appName;

  /// No description provided for @appVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get appVersion;

  /// No description provided for @authenticatorCode.
  ///
  /// In en, this message translates to:
  /// **'Authenticator code'**
  String get authenticatorCode;

  /// No description provided for @authenticatorCodeHelp.
  ///
  /// In en, this message translates to:
  /// **'The 6 digits from your authenticator app.'**
  String get authenticatorCodeHelp;

  /// No description provided for @availableBalance.
  ///
  /// In en, this message translates to:
  /// **'Available balance'**
  String get availableBalance;

  /// No description provided for @availableUpTo.
  ///
  /// In en, this message translates to:
  /// **'Up to {amount}'**
  String availableUpTo(String amount);

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @barcodeUnknown.
  ///
  /// In en, this message translates to:
  /// **'This barcode is not in the catalog.'**
  String get barcodeUnknown;

  /// No description provided for @cameraUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The camera is not available. Check the permission in your phone settings.'**
  String get cameraUnavailable;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get cancelRequest;

  /// No description provided for @cancelSale.
  ///
  /// In en, this message translates to:
  /// **'Cancel the sale'**
  String get cancelSale;

  /// No description provided for @cancelSaleBody.
  ///
  /// In en, this message translates to:
  /// **'The stock is put back and the reward is taken off your wallet.'**
  String get cancelSaleBody;

  /// No description provided for @cancelSaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this sale?'**
  String get cancelSaleTitle;

  /// No description provided for @celebrateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unit sold} other{{count} units sold}}'**
  String celebrateSubtitle(int count);

  /// No description provided for @celebrateTitle.
  ///
  /// In en, this message translates to:
  /// **'Great sale!'**
  String get celebrateTitle;

  /// No description provided for @celebrateToday.
  ///
  /// In en, this message translates to:
  /// **'Today so far'**
  String get celebrateToday;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @codeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid code.'**
  String get codeInvalid;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @correctSale.
  ///
  /// In en, this message translates to:
  /// **'Correct this sale'**
  String get correctSale;

  /// No description provided for @correctSaleHint.
  ///
  /// In en, this message translates to:
  /// **'Change the quantities. Set a product to 0 to remove it, or all to 0 to cancel the sale.'**
  String get correctSaleHint;

  /// No description provided for @corrected.
  ///
  /// In en, this message translates to:
  /// **'Corrected'**
  String get corrected;

  /// No description provided for @correctionWindowClosed.
  ///
  /// In en, this message translates to:
  /// **'A sale can be corrected for 48 hours. Ask your responsable for later corrections.'**
  String get correctionWindowClosed;

  /// No description provided for @corrections.
  ///
  /// In en, this message translates to:
  /// **'Corrections'**
  String get corrections;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @decrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get decrease;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draft;

  /// No description provided for @earnedToday.
  ///
  /// In en, this message translates to:
  /// **'Earned today'**
  String get earnedToday;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit my profile'**
  String get editProfile;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get emailInvalid;

  /// No description provided for @entryCorrection.
  ///
  /// In en, this message translates to:
  /// **'Correction'**
  String get entryCorrection;

  /// No description provided for @entryPayout.
  ///
  /// In en, this message translates to:
  /// **'Payout'**
  String get entryPayout;

  /// No description provided for @entrySale.
  ///
  /// In en, this message translates to:
  /// **'Sale reward'**
  String get entrySale;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errorGeneric;

  /// No description provided for @errorOffline.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your internet and try again.'**
  String get errorOffline;

  /// No description provided for @errorServer.
  ///
  /// In en, this message translates to:
  /// **'The service is temporarily unavailable. Try again shortly.'**
  String get errorServer;

  /// No description provided for @forgotCodeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the code from the email and your new password.'**
  String get forgotCodeSubtitle;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get forgotPassword;

  /// No description provided for @forgotSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We will email you a code, valid for 30 minutes.'**
  String get forgotSubtitle;

  /// No description provided for @forgotTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get forgotTitle;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @fullNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Your name (optional)'**
  String get fullNameOptional;

  /// No description provided for @haveCode.
  ///
  /// In en, this message translates to:
  /// **'I already have a code'**
  String get haveCode;

  /// No description provided for @helloName.
  ///
  /// In en, this message translates to:
  /// **'Hello, {name}'**
  String helloName(String name);

  /// No description provided for @increase.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get increase;

  /// No description provided for @invitedHint.
  ///
  /// In en, this message translates to:
  /// **'Your account was approved and you received a code by email?'**
  String get invitedHint;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @latestSales.
  ///
  /// In en, this message translates to:
  /// **'Latest sales'**
  String get latestSales;

  /// No description provided for @lessonArticle.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get lessonArticle;

  /// No description provided for @lessonPdf.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get lessonPdf;

  /// No description provided for @lessonVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get lessonVideo;

  /// No description provided for @lessonsDone.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} lessons'**
  String lessonsDone(int done, int total);

  /// No description provided for @manageTraining.
  ///
  /// In en, this message translates to:
  /// **'Manage courses'**
  String get manageTraining;

  /// No description provided for @markAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get markAllRead;

  /// No description provided for @markDone.
  ///
  /// In en, this message translates to:
  /// **'Mark as done'**
  String get markDone;

  /// No description provided for @markNotDone.
  ///
  /// In en, this message translates to:
  /// **'Mark as not done'**
  String get markNotDone;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutes(int count);

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @moreTitle.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreTitle;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @newSale.
  ///
  /// In en, this message translates to:
  /// **'New sale'**
  String get newSale;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @noActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get noActivityYet;

  /// No description provided for @noCourses.
  ///
  /// In en, this message translates to:
  /// **'No course yet'**
  String get noCourses;

  /// No description provided for @noCoursesHint.
  ///
  /// In en, this message translates to:
  /// **'New courses will appear here.'**
  String get noCoursesHint;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'Nothing new'**
  String get noNotifications;

  /// No description provided for @noNotificationsHint.
  ///
  /// In en, this message translates to:
  /// **'Announcements and updates will appear here.'**
  String get noNotificationsHint;

  /// No description provided for @noProductsFound.
  ///
  /// In en, this message translates to:
  /// **'No product found'**
  String get noProductsFound;

  /// No description provided for @noSalesYet.
  ///
  /// In en, this message translates to:
  /// **'No sales yet'**
  String get noSalesYet;

  /// No description provided for @noSalesYetHint.
  ///
  /// In en, this message translates to:
  /// **'Your sales and what they earned will appear here.'**
  String get noSalesYetHint;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @openDocument.
  ///
  /// In en, this message translates to:
  /// **'Open the document'**
  String get openDocument;

  /// No description provided for @openVideo.
  ///
  /// In en, this message translates to:
  /// **'Watch the video'**
  String get openVideo;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'optional'**
  String get optional;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordChanged.
  ///
  /// In en, this message translates to:
  /// **'Password changed. You can sign in.'**
  String get passwordChanged;

  /// No description provided for @passwordChangedShort.
  ///
  /// In en, this message translates to:
  /// **'Password changed'**
  String get passwordChangedShort;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get passwordRequired;

  /// No description provided for @passwordRule.
  ///
  /// In en, this message translates to:
  /// **'At least 10 characters.'**
  String get passwordRule;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 10 characters.'**
  String get passwordTooShort;

  /// No description provided for @passwordsDiffer.
  ///
  /// In en, this message translates to:
  /// **'The passwords do not match.'**
  String get passwordsDiffer;

  /// No description provided for @payoutExplain.
  ///
  /// In en, this message translates to:
  /// **'The admin will pay you and confirm. The amount leaves your wallet once approved.'**
  String get payoutExplain;

  /// No description provided for @payoutPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get payoutPaid;

  /// No description provided for @payoutRequested.
  ///
  /// In en, this message translates to:
  /// **'Payout requested'**
  String get payoutRequested;

  /// No description provided for @payouts.
  ///
  /// In en, this message translates to:
  /// **'Payouts'**
  String get payouts;

  /// No description provided for @pdvNotActive.
  ///
  /// In en, this message translates to:
  /// **'Your point of sale is waiting for approval. You can sell as soon as it is active.'**
  String get pdvNotActive;

  /// No description provided for @pendingPayout.
  ///
  /// In en, this message translates to:
  /// **'{amount} already requested'**
  String pendingPayout(String amount);

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @photoChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose from gallery'**
  String get photoChoose;

  /// No description provided for @photoHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to take a photo'**
  String get photoHint;

  /// No description provided for @photoReady.
  ///
  /// In en, this message translates to:
  /// **'Photo ready'**
  String get photoReady;

  /// No description provided for @photoRetake.
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get photoRetake;

  /// No description provided for @photoTake.
  ///
  /// In en, this message translates to:
  /// **'Take a photo'**
  String get photoTake;

  /// No description provided for @photoUploading.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get photoUploading;

  /// No description provided for @pinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinned;

  /// No description provided for @pointOfSale.
  ///
  /// In en, this message translates to:
  /// **'Point of sale'**
  String get pointOfSale;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @published.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get published;

  /// No description provided for @quantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantity;

  /// No description provided for @quantityMax.
  ///
  /// In en, this message translates to:
  /// **'Up to {max}'**
  String quantityMax(int max);

  /// No description provided for @reasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Reason (required)'**
  String get reasonRequired;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @recordSale.
  ///
  /// In en, this message translates to:
  /// **'Record the sale'**
  String get recordSale;

  /// No description provided for @recoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get recoveryCode;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @requestPayout.
  ///
  /// In en, this message translates to:
  /// **'Request a payout'**
  String get requestPayout;

  /// No description provided for @resetCodeSent.
  ///
  /// In en, this message translates to:
  /// **'If the account exists, a code was sent.'**
  String get resetCodeSent;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @reviewSale.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Review sale · 1 unit} other{Review sale · {count} units}}'**
  String reviewSale(int count);

  /// No description provided for @reviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review the sale'**
  String get reviewTitle;

  /// No description provided for @reward.
  ///
  /// In en, this message translates to:
  /// **'Reward'**
  String get reward;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Administrator'**
  String get roleAdmin;

  /// No description provided for @roleGrossiste.
  ///
  /// In en, this message translates to:
  /// **'Grossiste'**
  String get roleGrossiste;

  /// No description provided for @roleResponsable.
  ///
  /// In en, this message translates to:
  /// **'Responsable'**
  String get roleResponsable;

  /// No description provided for @roleVendeur.
  ///
  /// In en, this message translates to:
  /// **'Team member'**
  String get roleVendeur;

  /// No description provided for @saleCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sale cancelled'**
  String get saleCancelled;

  /// No description provided for @saleCorrected.
  ///
  /// In en, this message translates to:
  /// **'Sale corrected'**
  String get saleCorrected;

  /// No description provided for @saleDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get saleDetailTitle;

  /// No description provided for @saleRecordedTitle.
  ///
  /// In en, this message translates to:
  /// **'Sale recorded'**
  String get saleRecordedTitle;

  /// No description provided for @saleRefused.
  ///
  /// In en, this message translates to:
  /// **'The server refused this sale'**
  String get saleRefused;

  /// No description provided for @saleVoided.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get saleVoided;

  /// No description provided for @salesCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No sales} =1{1 sale} other{{count} sales}}'**
  String salesCount(int count);

  /// No description provided for @salesTitle.
  ///
  /// In en, this message translates to:
  /// **'My sales'**
  String get salesTitle;

  /// No description provided for @salesWaiting.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sale is waiting to be sent} other{{count} sales are waiting to be sent}}'**
  String salesWaiting(int count);

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saveCorrection.
  ///
  /// In en, this message translates to:
  /// **'Save the correction'**
  String get saveCorrection;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @savedOnPhoneBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unit} other{{count} units}} will be sent as soon as you are back online. Your reward will then appear.'**
  String savedOnPhoneBody(int count);

  /// No description provided for @savedOnPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved on your phone'**
  String get savedOnPhoneTitle;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the barcode'**
  String get scanHint;

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan a product'**
  String get scanTitle;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchProducts.
  ///
  /// In en, this message translates to:
  /// **'Search a product'**
  String get searchProducts;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @seller.
  ///
  /// In en, this message translates to:
  /// **'Seller'**
  String get seller;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send me a code'**
  String get sendCode;

  /// No description provided for @sendNow.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get sendNow;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to your BioBalance account.'**
  String get signInSubtitle;

  /// No description provided for @signInTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get signInTitle;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @signOutTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out of BioBalance?'**
  String get signOutTitle;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get statusRejected;

  /// No description provided for @tabHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get tabHome;

  /// No description provided for @tabLearn.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get tabLearn;

  /// No description provided for @tabSales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get tabSales;

  /// No description provided for @tabWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get tabWallet;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get thisMonth;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get thisWeek;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @torch.
  ///
  /// In en, this message translates to:
  /// **'Flashlight'**
  String get torch;

  /// No description provided for @totalUnits.
  ///
  /// In en, this message translates to:
  /// **'Total units'**
  String get totalUnits;

  /// No description provided for @trainingTitle.
  ///
  /// In en, this message translates to:
  /// **'Training'**
  String get trainingTitle;

  /// No description provided for @units.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unit} other{{count} units}}'**
  String units(int count);

  /// No description provided for @videoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This video cannot be played.'**
  String get videoUnavailable;

  /// No description provided for @waitingToSend.
  ///
  /// In en, this message translates to:
  /// **'Waiting to be sent'**
  String get waitingToSend;

  /// No description provided for @walletBalance.
  ///
  /// In en, this message translates to:
  /// **'Wallet balance'**
  String get walletBalance;

  /// No description provided for @walletTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get walletTitle;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @youEarned.
  ///
  /// In en, this message translates to:
  /// **'You earned'**
  String get youEarned;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
