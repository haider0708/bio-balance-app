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

  /// No description provided for @accountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account created and invitation sent'**
  String get accountCreated;

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

  /// No description provided for @activePdvs.
  ///
  /// In en, this message translates to:
  /// **'Active PDVs'**
  String get activePdvs;

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

  /// No description provided for @addLesson.
  ///
  /// In en, this message translates to:
  /// **'Add a lesson'**
  String get addLesson;

  /// No description provided for @addMember.
  ///
  /// In en, this message translates to:
  /// **'Add a member'**
  String get addMember;

  /// No description provided for @addMemberFromPdv.
  ///
  /// In en, this message translates to:
  /// **'Open a point of sale to add a team member.'**
  String get addMemberFromPdv;

  /// No description provided for @addMemberHint.
  ///
  /// In en, this message translates to:
  /// **'They can sign in once BioBalance approves them. They receive an email with a code.'**
  String get addMemberHint;

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

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @adjustQuantities.
  ///
  /// In en, this message translates to:
  /// **'Adjust quantities'**
  String get adjustQuantities;

  /// No description provided for @adjustQuantitiesHint.
  ///
  /// In en, this message translates to:
  /// **'Change what will be sent before choosing who sends it.'**
  String get adjustQuantitiesHint;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @allCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'Everything is up to date.'**
  String get allCaughtUp;

  /// No description provided for @allRegions.
  ///
  /// In en, this message translates to:
  /// **'All regions'**
  String get allRegions;

  /// No description provided for @amendAndApprove.
  ///
  /// In en, this message translates to:
  /// **'Correct and approve'**
  String get amendAndApprove;

  /// No description provided for @amendReceiptHint.
  ///
  /// In en, this message translates to:
  /// **'Compare with the photo of the paper and correct a quantity if needed.'**
  String get amendReceiptHint;

  /// No description provided for @amendStockHint.
  ///
  /// In en, this message translates to:
  /// **'Change a quantity if the photo shows something different.'**
  String get amendStockHint;

  /// No description provided for @amountPerUnit.
  ///
  /// In en, this message translates to:
  /// **'Amount per unit sold'**
  String get amountPerUnit;

  /// No description provided for @amountPerUnitHint.
  ///
  /// In en, this message translates to:
  /// **'Example: 0.500'**
  String get amountPerUnitHint;

  /// No description provided for @amountTnd.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountTnd;

  /// No description provided for @announcement.
  ///
  /// In en, this message translates to:
  /// **'Announcement'**
  String get announcement;

  /// No description provided for @announcementScheduled.
  ///
  /// In en, this message translates to:
  /// **'Announcement scheduled'**
  String get announcementScheduled;

  /// No description provided for @announcementSent.
  ///
  /// In en, this message translates to:
  /// **'Announcement sent'**
  String get announcementSent;

  /// No description provided for @announcementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get announcementsTitle;

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

  /// No description provided for @approvalGroups.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 group} other{{count} groups}}'**
  String approvalGroups(int count);

  /// No description provided for @approvalMembers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 team member} other{{count} team members}}'**
  String approvalMembers(int count);

  /// No description provided for @approvalPayouts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 payout} other{{count} payouts}}'**
  String approvalPayouts(int count);

  /// No description provided for @approvalPdvs.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 point of sale} other{{count} points of sale}}'**
  String approvalPdvs(int count);

  /// No description provided for @approvalReceipts.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 delivery} other{{count} deliveries}}'**
  String approvalReceipts(int count);

  /// No description provided for @approvalRequests.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 restock request} other{{count} restock requests}}'**
  String approvalRequests(int count);

  /// No description provided for @approvalStock.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stock} other{{count} stocks}}'**
  String approvalStock(int count);

  /// No description provided for @approvalsTitle.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get approvalsTitle;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @approveAndInvite.
  ///
  /// In en, this message translates to:
  /// **'Approve and send invitation'**
  String get approveAndInvite;

  /// No description provided for @approveAsCounted.
  ///
  /// In en, this message translates to:
  /// **'Approve as counted'**
  String get approveAsCounted;

  /// No description provided for @approveGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Approve the group “{name}”?'**
  String approveGroupTitle(String name);

  /// No description provided for @approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approved;

  /// No description provided for @askRecount.
  ///
  /// In en, this message translates to:
  /// **'Ask to count again'**
  String get askRecount;

  /// No description provided for @assignToGrossiste.
  ///
  /// In en, this message translates to:
  /// **'Assign to a grossiste'**
  String get assignToGrossiste;

  /// No description provided for @auditTitle.
  ///
  /// In en, this message translates to:
  /// **'History of changes'**
  String get auditTitle;

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

  /// No description provided for @balanceShort.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balanceShort;

  /// No description provided for @barcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode'**
  String get barcode;

  /// No description provided for @barcodeUnknown.
  ///
  /// In en, this message translates to:
  /// **'This barcode is not in the catalog.'**
  String get barcodeUnknown;

  /// No description provided for @byDay.
  ///
  /// In en, this message translates to:
  /// **'day'**
  String get byDay;

  /// No description provided for @byFamily.
  ///
  /// In en, this message translates to:
  /// **'By family'**
  String get byFamily;

  /// No description provided for @byName.
  ///
  /// In en, this message translates to:
  /// **'by {name}'**
  String byName(String name);

  /// No description provided for @byPdv.
  ///
  /// In en, this message translates to:
  /// **'point of sale'**
  String get byPdv;

  /// No description provided for @byProduct.
  ///
  /// In en, this message translates to:
  /// **'By product'**
  String get byProduct;

  /// No description provided for @byProductShort.
  ///
  /// In en, this message translates to:
  /// **'product'**
  String get byProductShort;

  /// No description provided for @byRegion.
  ///
  /// In en, this message translates to:
  /// **'region'**
  String get byRegion;

  /// No description provided for @bySeller.
  ///
  /// In en, this message translates to:
  /// **'seller'**
  String get bySeller;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

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

  /// No description provided for @cancelReason.
  ///
  /// In en, this message translates to:
  /// **'Reason for cancelling'**
  String get cancelReason;

  /// No description provided for @cancelReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Why is it cancelled?'**
  String get cancelReasonHint;

  /// No description provided for @cancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get cancelRequest;

  /// No description provided for @cancelRestock.
  ///
  /// In en, this message translates to:
  /// **'Cancel the restock'**
  String get cancelRestock;

  /// No description provided for @cancelRule.
  ///
  /// In en, this message translates to:
  /// **'Cancel this value'**
  String get cancelRule;

  /// No description provided for @cancelRuleBody.
  ///
  /// In en, this message translates to:
  /// **'Sales already made keep what they earned. Future sales will not earn it.'**
  String get cancelRuleBody;

  /// No description provided for @cancelRuleTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel this value?'**
  String get cancelRuleTitle;

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

  /// No description provided for @catalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get catalogTitle;

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

  /// No description provided for @changeReceiver.
  ///
  /// In en, this message translates to:
  /// **'Change who counts the goods'**
  String get changeReceiver;

  /// No description provided for @chooseAudience.
  ///
  /// In en, this message translates to:
  /// **'Choose who receives it'**
  String get chooseAudience;

  /// No description provided for @chooseGrossiste.
  ///
  /// In en, this message translates to:
  /// **'Choose a grossiste'**
  String get chooseGrossiste;

  /// No description provided for @choosePdvs.
  ///
  /// In en, this message translates to:
  /// **'Choose points of sale'**
  String get choosePdvs;

  /// No description provided for @chooseProduct.
  ///
  /// In en, this message translates to:
  /// **'Choose a product'**
  String get chooseProduct;

  /// No description provided for @chooseReceiver.
  ///
  /// In en, this message translates to:
  /// **'Choose who counts the goods'**
  String get chooseReceiver;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

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

  /// No description provided for @colApproved.
  ///
  /// In en, this message translates to:
  /// **'Final'**
  String get colApproved;

  /// No description provided for @colReceived.
  ///
  /// In en, this message translates to:
  /// **'Counted'**
  String get colReceived;

  /// No description provided for @colRequested.
  ///
  /// In en, this message translates to:
  /// **'Asked'**
  String get colRequested;

  /// No description provided for @colShipped.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get colShipped;

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

  /// No description provided for @confirmDelivery.
  ///
  /// In en, this message translates to:
  /// **'Confirm the delivery'**
  String get confirmDelivery;

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

  /// No description provided for @countedProducts.
  ///
  /// In en, this message translates to:
  /// **'Counted products'**
  String get countedProducts;

  /// No description provided for @counting.
  ///
  /// In en, this message translates to:
  /// **'Counting…'**
  String get counting;

  /// No description provided for @courseAudienceHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to show it to everyone.'**
  String get courseAudienceHint;

  /// No description provided for @courseDeleted.
  ///
  /// In en, this message translates to:
  /// **'Course deleted'**
  String get courseDeleted;

  /// No description provided for @courseIsDraft.
  ///
  /// In en, this message translates to:
  /// **'Course unpublished'**
  String get courseIsDraft;

  /// No description provided for @courseIsPublished.
  ///
  /// In en, this message translates to:
  /// **'Course published'**
  String get courseIsPublished;

  /// No description provided for @courseSummary.
  ///
  /// In en, this message translates to:
  /// **'Short description'**
  String get courseSummary;

  /// No description provided for @courseTitle.
  ///
  /// In en, this message translates to:
  /// **'Course title'**
  String get courseTitle;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @createAndInvite.
  ///
  /// In en, this message translates to:
  /// **'Create and send invitation'**
  String get createAndInvite;

  /// No description provided for @createPdv.
  ///
  /// In en, this message translates to:
  /// **'Create the point of sale'**
  String get createPdv;

  /// No description provided for @current.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get current;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get currentPassword;

  /// No description provided for @customPeriod.
  ///
  /// In en, this message translates to:
  /// **'Choose dates'**
  String get customPeriod;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @dateRange.
  ///
  /// In en, this message translates to:
  /// **'{from} → {to}'**
  String dateRange(String from, String to);

  /// No description provided for @deactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get deactivate;

  /// No description provided for @deactivateBody.
  ///
  /// In en, this message translates to:
  /// **'They will be signed out and will no longer have access.'**
  String get deactivateBody;

  /// No description provided for @deactivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate {name}?'**
  String deactivateTitle(String name);

  /// No description provided for @deactivated.
  ///
  /// In en, this message translates to:
  /// **'Deactivated'**
  String get deactivated;

  /// No description provided for @decision.
  ///
  /// In en, this message translates to:
  /// **'Decision'**
  String get decision;

  /// No description provided for @declaration.
  ///
  /// In en, this message translates to:
  /// **'Stock declaration'**
  String get declaration;

  /// No description provided for @declarationRejectedRetry.
  ///
  /// In en, this message translates to:
  /// **'Your last stock declaration was rejected. Declare it again.'**
  String get declarationRejectedRetry;

  /// No description provided for @declarationSent.
  ///
  /// In en, this message translates to:
  /// **'Sent to BioBalance for approval'**
  String get declarationSent;

  /// No description provided for @declarationWaiting.
  ///
  /// In en, this message translates to:
  /// **'A stock declaration is waiting for approval.'**
  String get declarationWaiting;

  /// No description provided for @declarations.
  ///
  /// In en, this message translates to:
  /// **'Declarations'**
  String get declarations;

  /// No description provided for @declareFirstHint.
  ///
  /// In en, this message translates to:
  /// **'Count every product you hold, add the quantities and take a photo of the stock. BioBalance checks it, then the stock becomes official.'**
  String get declareFirstHint;

  /// No description provided for @declareStock.
  ///
  /// In en, this message translates to:
  /// **'Declare the stock'**
  String get declareStock;

  /// No description provided for @declaredQuantity.
  ///
  /// In en, this message translates to:
  /// **'Declared: {count}'**
  String declaredQuantity(int count);

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @declinePayoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Why decline this payout?'**
  String get declinePayoutTitle;

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

  /// No description provided for @deleteCourse.
  ///
  /// In en, this message translates to:
  /// **'Delete the course'**
  String get deleteCourse;

  /// No description provided for @deleteCourseBody.
  ///
  /// In en, this message translates to:
  /// **'Its lessons and everyone’s progress are deleted.'**
  String get deleteCourseBody;

  /// No description provided for @deleteCourseTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this course?'**
  String get deleteCourseTitle;

  /// No description provided for @deleteLessonTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this lesson?'**
  String get deleteLessonTitle;

  /// No description provided for @deliverTo.
  ///
  /// In en, this message translates to:
  /// **'Deliver to'**
  String get deliverTo;

  /// No description provided for @deliveriesToConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 delivery to confirm} other{{count} deliveries to confirm}}'**
  String deliveriesToConfirm(int count);

  /// No description provided for @deliveriesToConfirmHint.
  ///
  /// In en, this message translates to:
  /// **'Photograph the paper and count the goods.'**
  String get deliveriesToConfirmHint;

  /// No description provided for @deliveryPaper.
  ///
  /// In en, this message translates to:
  /// **'Delivery paper'**
  String get deliveryPaper;

  /// No description provided for @deliverySent.
  ///
  /// In en, this message translates to:
  /// **'Sent to BioBalance for approval'**
  String get deliverySent;

  /// No description provided for @depotName.
  ///
  /// In en, this message translates to:
  /// **'Depot name'**
  String get depotName;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

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

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get durationMinutes;

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

  /// No description provided for @editCourse.
  ///
  /// In en, this message translates to:
  /// **'Edit course'**
  String get editCourse;

  /// No description provided for @editLesson.
  ///
  /// In en, this message translates to:
  /// **'Edit lesson'**
  String get editLesson;

  /// No description provided for @editPdv.
  ///
  /// In en, this message translates to:
  /// **'Edit point of sale'**
  String get editPdv;

  /// No description provided for @editProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit product'**
  String get editProduct;

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

  /// No description provided for @endsOn.
  ///
  /// In en, this message translates to:
  /// **'Ends {date}'**
  String endsOn(String date);

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

  /// No description provided for @everyone.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get everyone;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export to a spreadsheet'**
  String get exportCsv;

  /// No description provided for @family.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get family;

  /// No description provided for @familyHint.
  ///
  /// In en, this message translates to:
  /// **'Rewards can be set per family.'**
  String get familyHint;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get fieldRequired;

  /// No description provided for @fileAttached.
  ///
  /// In en, this message translates to:
  /// **'File attached'**
  String get fileAttached;

  /// No description provided for @filterDone.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get filterDone;

  /// No description provided for @filterOpen.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get filterOpen;

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

  /// No description provided for @fromDate.
  ///
  /// In en, this message translates to:
  /// **'From {date}'**
  String fromDate(String date);

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

  /// No description provided for @grossisteDeclareFirst.
  ///
  /// In en, this message translates to:
  /// **'Declare your depot stock with a photo so BioBalance can approve it.'**
  String get grossisteDeclareFirst;

  /// No description provided for @grossistesTitle.
  ///
  /// In en, this message translates to:
  /// **'Grossistes'**
  String get grossistesTitle;

  /// No description provided for @group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// No description provided for @groupCreated.
  ///
  /// In en, this message translates to:
  /// **'Group created. It is waiting for approval.'**
  String get groupCreated;

  /// No description provided for @groupName.
  ///
  /// In en, this message translates to:
  /// **'Group name'**
  String get groupName;

  /// No description provided for @groupedBy.
  ///
  /// In en, this message translates to:
  /// **'By'**
  String get groupedBy;

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

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @howToUse.
  ///
  /// In en, this message translates to:
  /// **'How to use'**
  String get howToUse;

  /// No description provided for @inRegions.
  ///
  /// In en, this message translates to:
  /// **'In these regions'**
  String get inRegions;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @increase.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get increase;

  /// No description provided for @ingredients.
  ///
  /// In en, this message translates to:
  /// **'Ingredients'**
  String get ingredients;

  /// No description provided for @initialStock.
  ///
  /// In en, this message translates to:
  /// **'Opening stock'**
  String get initialStock;

  /// No description provided for @invitationResent.
  ///
  /// In en, this message translates to:
  /// **'Invitation sent again'**
  String get invitationResent;

  /// No description provided for @invitationSent.
  ///
  /// In en, this message translates to:
  /// **'Invitation sent'**
  String get invitationSent;

  /// No description provided for @invitedHint.
  ///
  /// In en, this message translates to:
  /// **'Your account was approved and you received a code by email?'**
  String get invitedHint;

  /// No description provided for @kind.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get kind;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// No description provided for @lastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get lastMonth;

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

  /// No description provided for @lessonText.
  ///
  /// In en, this message translates to:
  /// **'Text of the lesson'**
  String get lessonText;

  /// No description provided for @lessonTitle.
  ///
  /// In en, this message translates to:
  /// **'Lesson title'**
  String get lessonTitle;

  /// No description provided for @lessonVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get lessonVideo;

  /// No description provided for @lessons.
  ///
  /// In en, this message translates to:
  /// **'Lessons'**
  String get lessons;

  /// No description provided for @lessonsDone.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} lessons'**
  String lessonsDone(int done, int total);

  /// No description provided for @lowStock.
  ///
  /// In en, this message translates to:
  /// **'Products almost out'**
  String get lowStock;

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

  /// No description provided for @markAsPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark as paid'**
  String get markAsPaid;

  /// No description provided for @markAsPaidHint.
  ///
  /// In en, this message translates to:
  /// **'Confirm you paid {amount}. It leaves their wallet.'**
  String markAsPaidHint(String amount);

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

  /// No description provided for @markShipped.
  ///
  /// In en, this message translates to:
  /// **'Mark as shipped'**
  String get markShipped;

  /// No description provided for @me.
  ///
  /// In en, this message translates to:
  /// **'Me'**
  String get me;

  /// No description provided for @memberAdded.
  ///
  /// In en, this message translates to:
  /// **'Member added. Waiting for approval.'**
  String get memberAdded;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

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

  /// No description provided for @myRegion.
  ///
  /// In en, this message translates to:
  /// **'Region {name}'**
  String myRegion(String name);

  /// No description provided for @myRestockRequests.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No restock request in progress} =1{1 of your restock requests is in progress} other{{count} of your restock requests are in progress}}'**
  String myRestockRequests(int count);

  /// No description provided for @needsAttention.
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get needsAttention;

  /// No description provided for @negativeStock.
  ///
  /// In en, this message translates to:
  /// **'Products below zero'**
  String get negativeStock;

  /// No description provided for @networkTitle.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get networkTitle;

  /// No description provided for @newAccount.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get newAccount;

  /// No description provided for @newAccountHint.
  ///
  /// In en, this message translates to:
  /// **'The person receives an email with a code to choose their password.'**
  String get newAccountHint;

  /// No description provided for @newAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'New announcement'**
  String get newAnnouncement;

  /// No description provided for @newCourse.
  ///
  /// In en, this message translates to:
  /// **'New course'**
  String get newCourse;

  /// No description provided for @newGroup.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroup;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @newPdv.
  ///
  /// In en, this message translates to:
  /// **'New point of sale'**
  String get newPdv;

  /// No description provided for @newPdvHint.
  ///
  /// In en, this message translates to:
  /// **'It can be used right away for setup. BioBalance approves it before it sells.'**
  String get newPdvHint;

  /// No description provided for @newProduct.
  ///
  /// In en, this message translates to:
  /// **'New product'**
  String get newProduct;

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

  /// No description provided for @noActivePdv.
  ///
  /// In en, this message translates to:
  /// **'You need an approved point of sale to request a restock.'**
  String get noActivePdv;

  /// No description provided for @noActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get noActivityYet;

  /// No description provided for @noAnnouncements.
  ///
  /// In en, this message translates to:
  /// **'No announcement yet'**
  String get noAnnouncements;

  /// No description provided for @noAnnouncementsHint.
  ///
  /// In en, this message translates to:
  /// **'Write to responsables, grossistes or teams.'**
  String get noAnnouncementsHint;

  /// No description provided for @noCourses.
  ///
  /// In en, this message translates to:
  /// **'No course yet'**
  String get noCourses;

  /// No description provided for @noCoursesAdminHint.
  ///
  /// In en, this message translates to:
  /// **'Create a course, add lessons, then publish it.'**
  String get noCoursesAdminHint;

  /// No description provided for @noCoursesHint.
  ///
  /// In en, this message translates to:
  /// **'New courses will appear here.'**
  String get noCoursesHint;

  /// No description provided for @noEndDate.
  ///
  /// In en, this message translates to:
  /// **'No end date'**
  String get noEndDate;

  /// No description provided for @noGrossisteShort.
  ///
  /// In en, this message translates to:
  /// **'No grossiste yet'**
  String get noGrossisteShort;

  /// No description provided for @noGrossisteYet.
  ///
  /// In en, this message translates to:
  /// **'No grossiste yet. Create an account for one first.'**
  String get noGrossisteYet;

  /// No description provided for @noGroup.
  ///
  /// In en, this message translates to:
  /// **'No group'**
  String get noGroup;

  /// No description provided for @noGroups.
  ///
  /// In en, this message translates to:
  /// **'No group yet'**
  String get noGroups;

  /// No description provided for @noGroupsHint.
  ///
  /// In en, this message translates to:
  /// **'A group gathers several points of sale of the same owner.'**
  String get noGroupsHint;

  /// No description provided for @noHistoryYet.
  ///
  /// In en, this message translates to:
  /// **'No decision yet'**
  String get noHistoryYet;

  /// No description provided for @noLessonsYet.
  ///
  /// In en, this message translates to:
  /// **'No lesson yet. Add one to publish the course.'**
  String get noLessonsYet;

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

  /// No description provided for @noOrdersToPrepare.
  ///
  /// In en, this message translates to:
  /// **'No order to prepare'**
  String get noOrdersToPrepare;

  /// No description provided for @noPayoutRequests.
  ///
  /// In en, this message translates to:
  /// **'No payout request'**
  String get noPayoutRequests;

  /// No description provided for @noPayoutsYet.
  ///
  /// In en, this message translates to:
  /// **'No payout yet'**
  String get noPayoutsYet;

  /// No description provided for @noPdvs.
  ///
  /// In en, this message translates to:
  /// **'No point of sale yet'**
  String get noPdvs;

  /// No description provided for @noPdvsHint.
  ///
  /// In en, this message translates to:
  /// **'Add your first point of sale with the button below.'**
  String get noPdvsHint;

  /// No description provided for @noPeople.
  ///
  /// In en, this message translates to:
  /// **'Nobody here yet'**
  String get noPeople;

  /// No description provided for @noProductsFound.
  ///
  /// In en, this message translates to:
  /// **'No product found'**
  String get noProductsFound;

  /// No description provided for @noRestocks.
  ///
  /// In en, this message translates to:
  /// **'No restock'**
  String get noRestocks;

  /// No description provided for @noRestocksHint.
  ///
  /// In en, this message translates to:
  /// **'Request products for a point of sale when it runs low.'**
  String get noRestocksHint;

  /// No description provided for @noRewardsYet.
  ///
  /// In en, this message translates to:
  /// **'No reward set yet'**
  String get noRewardsYet;

  /// No description provided for @noRewardsYetHint.
  ///
  /// In en, this message translates to:
  /// **'Choose a family or a product and an amount per unit sold.'**
  String get noRewardsYetHint;

  /// No description provided for @noRulesHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing here'**
  String get noRulesHere;

  /// No description provided for @noSalesInPeriod.
  ///
  /// In en, this message translates to:
  /// **'No sales in this period'**
  String get noSalesInPeriod;

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

  /// No description provided for @noStockYet.
  ///
  /// In en, this message translates to:
  /// **'No stock yet'**
  String get noStockYet;

  /// No description provided for @noStockYetHint.
  ///
  /// In en, this message translates to:
  /// **'Count what you have, take a photo and send it to BioBalance.'**
  String get noStockYetHint;

  /// No description provided for @noTeamYet.
  ///
  /// In en, this message translates to:
  /// **'No team member yet.'**
  String get noTeamYet;

  /// No description provided for @noWalletsYet.
  ///
  /// In en, this message translates to:
  /// **'No wallet yet'**
  String get noWalletsYet;

  /// No description provided for @none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// No description provided for @notReadYet.
  ///
  /// In en, this message translates to:
  /// **'Not read yet'**
  String get notReadYet;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @nothingToApprove.
  ///
  /// In en, this message translates to:
  /// **'Nothing to approve'**
  String get nothingToApprove;

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

  /// No description provided for @openRestocks.
  ///
  /// In en, this message translates to:
  /// **'Restocks in progress'**
  String get openRestocks;

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

  /// No description provided for @orVideoLink.
  ///
  /// In en, this message translates to:
  /// **'Or a video link'**
  String get orVideoLink;

  /// No description provided for @ordersTitle.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get ordersTitle;

  /// No description provided for @ordersToPrepare.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 order to prepare} other{{count} orders to prepare}}'**
  String ordersToPrepare(int count);

  /// No description provided for @overlapBody.
  ///
  /// In en, this message translates to:
  /// **'These days are already covered:\n{details}\n\nReplace it with the new value?'**
  String overlapBody(String details);

  /// No description provided for @overlapTitle.
  ///
  /// In en, this message translates to:
  /// **'Another value already applies'**
  String get overlapTitle;

  /// No description provided for @packageSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get packageSize;

  /// No description provided for @paidOn.
  ///
  /// In en, this message translates to:
  /// **'Paid on {date}'**
  String paidOn(String date);

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
  /// **'At least 8 characters.'**
  String get passwordRule;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters.'**
  String get passwordTooShort;

  /// No description provided for @passwordsDiffer.
  ///
  /// In en, this message translates to:
  /// **'The passwords do not match.'**
  String get passwordsDiffer;

  /// No description provided for @past.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get past;

  /// No description provided for @payoutApproved.
  ///
  /// In en, this message translates to:
  /// **'Payout recorded'**
  String get payoutApproved;

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

  /// No description provided for @payoutRequests.
  ///
  /// In en, this message translates to:
  /// **'Payout requests'**
  String get payoutRequests;

  /// No description provided for @payouts.
  ///
  /// In en, this message translates to:
  /// **'Payouts'**
  String get payouts;

  /// No description provided for @payoutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Payouts'**
  String get payoutsTitle;

  /// No description provided for @paysToday.
  ///
  /// In en, this message translates to:
  /// **'Pays today'**
  String get paysToday;

  /// No description provided for @paysTodayHint.
  ///
  /// In en, this message translates to:
  /// **'What one unit sold pays today, product by product.'**
  String get paysTodayHint;

  /// No description provided for @pdvCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No point of sale} =1{1 point of sale} other{{count} points of sale}}'**
  String pdvCount(int count);

  /// No description provided for @pdvCreated.
  ///
  /// In en, this message translates to:
  /// **'Point of sale created. It is waiting for approval.'**
  String get pdvCreated;

  /// No description provided for @pdvName.
  ///
  /// In en, this message translates to:
  /// **'Name of the point of sale'**
  String get pdvName;

  /// No description provided for @pdvNotActive.
  ///
  /// In en, this message translates to:
  /// **'Your point of sale is waiting for approval. You can sell as soon as it is active.'**
  String get pdvNotActive;

  /// No description provided for @pdvWaitingNotice.
  ///
  /// In en, this message translates to:
  /// **'Waiting for BioBalance to approve. You can already add the team and declare the stock.'**
  String get pdvWaitingNotice;

  /// No description provided for @pdvsChosen.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 point of sale chosen} other{{count} points of sale chosen}}'**
  String pdvsChosen(int count);

  /// No description provided for @pendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} waiting'**
  String pendingCount(int count);

  /// No description provided for @pendingPayout.
  ///
  /// In en, this message translates to:
  /// **'{amount} already requested'**
  String pendingPayout(String amount);

  /// No description provided for @people.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get people;

  /// No description provided for @perUnit.
  ///
  /// In en, this message translates to:
  /// **'per unit'**
  String get perUnit;

  /// No description provided for @periods.
  ///
  /// In en, this message translates to:
  /// **'Periods'**
  String get periods;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @photo.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get photo;

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

  /// No description provided for @photoOfPaper.
  ///
  /// In en, this message translates to:
  /// **'Photo of the delivery paper'**
  String get photoOfPaper;

  /// No description provided for @photoOfStock.
  ///
  /// In en, this message translates to:
  /// **'Photo of the stock'**
  String get photoOfStock;

  /// No description provided for @photoReady.
  ///
  /// In en, this message translates to:
  /// **'Photo ready'**
  String get photoReady;

  /// No description provided for @photoRequiredHint.
  ///
  /// In en, this message translates to:
  /// **'Take the photo to send.'**
  String get photoRequiredHint;

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

  /// No description provided for @pinAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'Pin to the top'**
  String get pinAnnouncement;

  /// No description provided for @pinAnnouncementHint.
  ///
  /// In en, this message translates to:
  /// **'It stays at the top of their notifications.'**
  String get pinAnnouncementHint;

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

  /// No description provided for @precautions.
  ///
  /// In en, this message translates to:
  /// **'Precautions'**
  String get precautions;

  /// No description provided for @prepareAndShip.
  ///
  /// In en, this message translates to:
  /// **'Prepare and ship'**
  String get prepareAndShip;

  /// No description provided for @productActive.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get productActive;

  /// No description provided for @productActiveHint.
  ///
  /// In en, this message translates to:
  /// **'Hidden from sales and orders when off.'**
  String get productActiveHint;

  /// No description provided for @productName.
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get productName;

  /// No description provided for @productPhoto.
  ///
  /// In en, this message translates to:
  /// **'Product photo'**
  String get productPhoto;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @productsNeeded.
  ///
  /// In en, this message translates to:
  /// **'Products needed'**
  String get productsNeeded;

  /// No description provided for @progress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progress;

  /// No description provided for @progressByPerson.
  ///
  /// In en, this message translates to:
  /// **'Progress by person'**
  String get progressByPerson;

  /// No description provided for @publish.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get publish;

  /// No description provided for @published.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get published;

  /// No description provided for @quantitiesAdjusted.
  ///
  /// In en, this message translates to:
  /// **'Quantities adjusted'**
  String get quantitiesAdjusted;

  /// No description provided for @quantitiesReceived.
  ///
  /// In en, this message translates to:
  /// **'Quantities received'**
  String get quantitiesReceived;

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

  /// No description provided for @reactivate.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get reactivate;

  /// No description provided for @reactivated.
  ///
  /// In en, this message translates to:
  /// **'Reactivated'**
  String get reactivated;

  /// No description provided for @readAt.
  ///
  /// In en, this message translates to:
  /// **'Read {date}'**
  String readAt(String date);

  /// No description provided for @readOf.
  ///
  /// In en, this message translates to:
  /// **'{read} of {total} read'**
  String readOf(int read, int total);

  /// No description provided for @reasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Reason (required)'**
  String get reasonRequired;

  /// No description provided for @receiveHint.
  ///
  /// In en, this message translates to:
  /// **'Photograph the signed delivery paper and enter what you really received for each product.'**
  String get receiveHint;

  /// No description provided for @receivedBy.
  ///
  /// In en, this message translates to:
  /// **'Counted by'**
  String get receivedBy;

  /// No description provided for @receiverSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get receiverSaved;

  /// No description provided for @recent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recent;

  /// No description provided for @recipients.
  ///
  /// In en, this message translates to:
  /// **'Recipients'**
  String get recipients;

  /// No description provided for @recordSale.
  ///
  /// In en, this message translates to:
  /// **'Record the sale'**
  String get recordSale;

  /// No description provided for @recount.
  ///
  /// In en, this message translates to:
  /// **'Recount'**
  String get recount;

  /// No description provided for @recountAsked.
  ///
  /// In en, this message translates to:
  /// **'Sent back for a new count'**
  String get recountAsked;

  /// No description provided for @recountHint.
  ///
  /// In en, this message translates to:
  /// **'The quantities below are what the system holds. Correct them to what you count, add a photo, and send.'**
  String get recountHint;

  /// No description provided for @recountReasonHint.
  ///
  /// In en, this message translates to:
  /// **'What does not match the paper?'**
  String get recountReasonHint;

  /// No description provided for @recountStock.
  ///
  /// In en, this message translates to:
  /// **'Recount the stock'**
  String get recountStock;

  /// No description provided for @recoveryCode.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get recoveryCode;

  /// No description provided for @reference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get reference;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @region.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get region;

  /// No description provided for @regionOf.
  ///
  /// In en, this message translates to:
  /// **'Region {name}'**
  String regionOf(String name);

  /// No description provided for @regions.
  ///
  /// In en, this message translates to:
  /// **'Regions'**
  String get regions;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @rejectReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Explain what to fix so it can be sent again.'**
  String get rejectReasonHint;

  /// No description provided for @rejectReasonTitle.
  ///
  /// In en, this message translates to:
  /// **'Why is it rejected?'**
  String get rejectReasonTitle;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @replaceValue.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replaceValue;

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// No description provided for @requestPayout.
  ///
  /// In en, this message translates to:
  /// **'Request a payout'**
  String get requestPayout;

  /// No description provided for @requestRestock.
  ///
  /// In en, this message translates to:
  /// **'Request a restock'**
  String get requestRestock;

  /// No description provided for @requestedBy.
  ///
  /// In en, this message translates to:
  /// **'Requested by'**
  String get requestedBy;

  /// No description provided for @requestedInStock.
  ///
  /// In en, this message translates to:
  /// **'Asked {requested} · in stock {stock}'**
  String requestedInStock(int requested, int stock);

  /// No description provided for @requestedQuantity.
  ///
  /// In en, this message translates to:
  /// **'Requested: {count}'**
  String requestedQuantity(int count);

  /// No description provided for @resendInvitation.
  ///
  /// In en, this message translates to:
  /// **'Send the invitation again'**
  String get resendInvitation;

  /// No description provided for @resetCodeSent.
  ///
  /// In en, this message translates to:
  /// **'If the account exists, a code was sent.'**
  String get resetCodeSent;

  /// No description provided for @restock.
  ///
  /// In en, this message translates to:
  /// **'Restock'**
  String get restock;

  /// No description provided for @restockApproved.
  ///
  /// In en, this message translates to:
  /// **'Restock approved. The stock is updated.'**
  String get restockApproved;

  /// No description provided for @restockAssigned.
  ///
  /// In en, this message translates to:
  /// **'With the grossiste'**
  String get restockAssigned;

  /// No description provided for @restockCancelled.
  ///
  /// In en, this message translates to:
  /// **'Restock cancelled'**
  String get restockCancelled;

  /// No description provided for @restockCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get restockCompleted;

  /// No description provided for @restockReceived.
  ///
  /// In en, this message translates to:
  /// **'To approve'**
  String get restockReceived;

  /// No description provided for @restockRequested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get restockRequested;

  /// No description provided for @restockRouted.
  ///
  /// In en, this message translates to:
  /// **'The order was sent on'**
  String get restockRouted;

  /// No description provided for @restockSent.
  ///
  /// In en, this message translates to:
  /// **'Request sent'**
  String get restockSent;

  /// No description provided for @restockShipped.
  ///
  /// In en, this message translates to:
  /// **'On its way'**
  String get restockShipped;

  /// No description provided for @restockShippedMessage.
  ///
  /// In en, this message translates to:
  /// **'Marked as shipped'**
  String get restockShippedMessage;

  /// No description provided for @restocksTitle.
  ///
  /// In en, this message translates to:
  /// **'Restocks'**
  String get restocksTitle;

  /// No description provided for @resubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit again'**
  String get resubmit;

  /// No description provided for @resubmitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted again'**
  String get resubmitted;

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

  /// No description provided for @rewardSaved.
  ///
  /// In en, this message translates to:
  /// **'Reward saved'**
  String get rewardSaved;

  /// No description provided for @rewardsMonth.
  ///
  /// In en, this message translates to:
  /// **'Rewards, 30 days'**
  String get rewardsMonth;

  /// No description provided for @rewardsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rewards'**
  String get rewardsTitle;

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

  /// No description provided for @roleGrossistePlural.
  ///
  /// In en, this message translates to:
  /// **'Grossistes'**
  String get roleGrossistePlural;

  /// No description provided for @roleResponsable.
  ///
  /// In en, this message translates to:
  /// **'Responsable'**
  String get roleResponsable;

  /// No description provided for @roleResponsablePlural.
  ///
  /// In en, this message translates to:
  /// **'Responsables'**
  String get roleResponsablePlural;

  /// No description provided for @roleVendeur.
  ///
  /// In en, this message translates to:
  /// **'Team member'**
  String get roleVendeur;

  /// No description provided for @roleVendeurPlural.
  ///
  /// In en, this message translates to:
  /// **'Team members'**
  String get roleVendeurPlural;

  /// No description provided for @roleVendeurShort.
  ///
  /// In en, this message translates to:
  /// **'Team member'**
  String get roleVendeurShort;

  /// No description provided for @ruleCancelled.
  ///
  /// In en, this message translates to:
  /// **'Value cancelled'**
  String get ruleCancelled;

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

  /// No description provided for @salesLast14Days.
  ///
  /// In en, this message translates to:
  /// **'Units sold, last 14 days'**
  String get salesLast14Days;

  /// No description provided for @salesTitle.
  ///
  /// In en, this message translates to:
  /// **'My sales'**
  String get salesTitle;

  /// No description provided for @salesTitleShort.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesTitleShort;

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

  /// No description provided for @saveReward.
  ///
  /// In en, this message translates to:
  /// **'Save the reward'**
  String get saveReward;

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

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @scheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule this announcement?'**
  String get scheduleTitle;

  /// No description provided for @scheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get scheduled;

  /// No description provided for @scheduledFor.
  ///
  /// In en, this message translates to:
  /// **'Scheduled for {date}'**
  String scheduledFor(String date);

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

  /// No description provided for @sendForApproval.
  ///
  /// In en, this message translates to:
  /// **'Send for approval'**
  String get sendForApproval;

  /// No description provided for @sendFromBiobalance.
  ///
  /// In en, this message translates to:
  /// **'Send from BioBalance'**
  String get sendFromBiobalance;

  /// No description provided for @sendNow.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get sendNow;

  /// No description provided for @sendNowOption.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get sendNowOption;

  /// No description provided for @sendNowTitle.
  ///
  /// In en, this message translates to:
  /// **'Send to {count, plural, =1{1 person} other{{count} people}}?'**
  String sendNowTitle(int count);

  /// No description provided for @sendRequest.
  ///
  /// In en, this message translates to:
  /// **'Send the request'**
  String get sendRequest;

  /// No description provided for @sendToAdmin.
  ///
  /// In en, this message translates to:
  /// **'Send to BioBalance'**
  String get sendToAdmin;

  /// No description provided for @sentBy.
  ///
  /// In en, this message translates to:
  /// **'Sent by'**
  String get sentBy;

  /// No description provided for @sentFrom.
  ///
  /// In en, this message translates to:
  /// **'Sent from'**
  String get sentFrom;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @setReward.
  ///
  /// In en, this message translates to:
  /// **'Set a reward'**
  String get setReward;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @shipHint.
  ///
  /// In en, this message translates to:
  /// **'Enter what leaves your depot for {destination}.'**
  String shipHint(String destination);

  /// No description provided for @shippedReceived.
  ///
  /// In en, this message translates to:
  /// **'Sent {shipped} · counted {received}'**
  String shippedReceived(int shipped, int received);

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

  /// No description provided for @startsOn.
  ///
  /// In en, this message translates to:
  /// **'Starts {date}'**
  String startsOn(String date);

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

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

  /// No description provided for @statusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get statusSuspended;

  /// No description provided for @statusWaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get statusWaitingApproval;

  /// No description provided for @stockAllGood.
  ///
  /// In en, this message translates to:
  /// **'All stock levels are fine'**
  String get stockAllGood;

  /// No description provided for @stockApproved.
  ///
  /// In en, this message translates to:
  /// **'Stock approved'**
  String get stockApproved;

  /// No description provided for @stockApprovedLong.
  ///
  /// In en, this message translates to:
  /// **'Stock approved: see quantities'**
  String get stockApprovedLong;

  /// No description provided for @stockLevels.
  ///
  /// In en, this message translates to:
  /// **'Quantities'**
  String get stockLevels;

  /// No description provided for @stockLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get stockLow;

  /// No description provided for @stockMissing.
  ///
  /// In en, this message translates to:
  /// **'No stock yet'**
  String get stockMissing;

  /// No description provided for @stockMissingLong.
  ///
  /// In en, this message translates to:
  /// **'Declare the opening stock with a photo'**
  String get stockMissingLong;

  /// No description provided for @stockNegative.
  ///
  /// In en, this message translates to:
  /// **'Below zero'**
  String get stockNegative;

  /// No description provided for @stockRejected.
  ///
  /// In en, this message translates to:
  /// **'Stock rejected'**
  String get stockRejected;

  /// No description provided for @stockRejectedLong.
  ///
  /// In en, this message translates to:
  /// **'Stock rejected: declare it again'**
  String get stockRejectedLong;

  /// No description provided for @stockTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stockTitle;

  /// No description provided for @stockWaiting.
  ///
  /// In en, this message translates to:
  /// **'Stock waiting'**
  String get stockWaiting;

  /// No description provided for @stockWaitingLong.
  ///
  /// In en, this message translates to:
  /// **'Stock waiting for approval'**
  String get stockWaitingLong;

  /// No description provided for @suspend.
  ///
  /// In en, this message translates to:
  /// **'Suspend'**
  String get suspend;

  /// No description provided for @suspendPdvBody.
  ///
  /// In en, this message translates to:
  /// **'Its team can no longer sell until it is reactivated.'**
  String get suspendPdvBody;

  /// No description provided for @suspendTitle.
  ///
  /// In en, this message translates to:
  /// **'Suspend {name}?'**
  String suspendTitle(String name);

  /// No description provided for @suspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get suspended;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @tabApprovals.
  ///
  /// In en, this message translates to:
  /// **'Approvals'**
  String get tabApprovals;

  /// No description provided for @tabGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get tabGroups;

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

  /// No description provided for @tabNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get tabNetwork;

  /// No description provided for @tabOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get tabOrders;

  /// No description provided for @tabPdvs.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get tabPdvs;

  /// No description provided for @tabPeople.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get tabPeople;

  /// No description provided for @tabReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get tabReports;

  /// No description provided for @tabRestocks.
  ///
  /// In en, this message translates to:
  /// **'Restocks'**
  String get tabRestocks;

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

  /// No description provided for @team.
  ///
  /// In en, this message translates to:
  /// **'Team'**
  String get team;

  /// No description provided for @teamCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No team} =1{1 member} other{{count} members}}'**
  String teamCount(int count);

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

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @toPay.
  ///
  /// In en, this message translates to:
  /// **'To pay'**
  String get toPay;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @topPdvs.
  ///
  /// In en, this message translates to:
  /// **'Top points of sale, 30 days'**
  String get topPdvs;

  /// No description provided for @topProducts.
  ///
  /// In en, this message translates to:
  /// **'Top products, 30 days'**
  String get topProducts;

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

  /// No description provided for @trendSemantics.
  ///
  /// In en, this message translates to:
  /// **'Chart: {total} units sold over the last 14 days'**
  String trendSemantics(int total);

  /// No description provided for @typeGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get typeGroup;

  /// No description provided for @typeMember.
  ///
  /// In en, this message translates to:
  /// **'Team member'**
  String get typeMember;

  /// No description provided for @typePayout.
  ///
  /// In en, this message translates to:
  /// **'Payout'**
  String get typePayout;

  /// No description provided for @typePdv.
  ///
  /// In en, this message translates to:
  /// **'Point of sale'**
  String get typePdv;

  /// No description provided for @typeReceipt.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get typeReceipt;

  /// No description provided for @typeRestockRequest.
  ///
  /// In en, this message translates to:
  /// **'Restock request'**
  String get typeRestockRequest;

  /// No description provided for @typeStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get typeStock;

  /// No description provided for @units.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unit} other{{count} units}}'**
  String units(int count);

  /// No description provided for @unpublish.
  ///
  /// In en, this message translates to:
  /// **'Unpublish'**
  String get unpublish;

  /// No description provided for @upcoming.
  ///
  /// In en, this message translates to:
  /// **'Upcoming'**
  String get upcoming;

  /// No description provided for @uploadPdf.
  ///
  /// In en, this message translates to:
  /// **'Upload a PDF'**
  String get uploadPdf;

  /// No description provided for @uploadVideo.
  ///
  /// In en, this message translates to:
  /// **'Upload a video (MP4)'**
  String get uploadVideo;

  /// No description provided for @videoUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This video cannot be played.'**
  String get videoUnavailable;

  /// No description provided for @viewSales.
  ///
  /// In en, this message translates to:
  /// **'View sales'**
  String get viewSales;

  /// No description provided for @waitingAdmin.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item is waiting for BioBalance to approve} other{{count} items are waiting for BioBalance to approve}}'**
  String waitingAdmin(int count);

  /// No description provided for @waitingForYou.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item is waiting for you} other{{count} items are waiting for you}}'**
  String waitingForYou(int count);

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

  /// No description provided for @walletSummaryLine.
  ///
  /// In en, this message translates to:
  /// **'Earned {earned} · paid {paid}'**
  String walletSummaryLine(String earned, String paid);

  /// No description provided for @walletTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get walletTitle;

  /// No description provided for @wallets.
  ///
  /// In en, this message translates to:
  /// **'Wallets'**
  String get wallets;

  /// No description provided for @whoCountsHint.
  ///
  /// In en, this message translates to:
  /// **'They will photograph the paper and enter the quantities.'**
  String get whoCountsHint;

  /// No description provided for @whoCountsTheGoods.
  ///
  /// In en, this message translates to:
  /// **'Who counts the goods?'**
  String get whoCountsTheGoods;

  /// No description provided for @whoIsItFor.
  ///
  /// In en, this message translates to:
  /// **'Who is it for?'**
  String get whoIsItFor;

  /// No description provided for @wholeNetwork.
  ///
  /// In en, this message translates to:
  /// **'Whole network'**
  String get wholeNetwork;

  /// No description provided for @willReach.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Nobody would receive it} =1{1 person will receive it} other{{count} people will receive it}}'**
  String willReach(int count);

  /// No description provided for @withdrawAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'Withdraw the announcement'**
  String get withdrawAnnouncement;

  /// No description provided for @withdrawBody.
  ///
  /// In en, this message translates to:
  /// **'It has not been sent yet and will not go out.'**
  String get withdrawBody;

  /// No description provided for @withdrawTitle.
  ///
  /// In en, this message translates to:
  /// **'Withdraw this announcement?'**
  String get withdrawTitle;

  /// No description provided for @withdrawn.
  ///
  /// In en, this message translates to:
  /// **'Announcement withdrawn'**
  String get withdrawn;

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

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @chooseStoreForMember.
  ///
  /// In en, this message translates to:
  /// **'Which store is this person joining?'**
  String get chooseStoreForMember;

  /// No description provided for @inStockCount.
  ///
  /// In en, this message translates to:
  /// **'{count} in stock'**
  String inStockCount(int count);

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStock;

  /// No description provided for @noStockHere.
  ///
  /// In en, this message translates to:
  /// **'This store has no stock yet'**
  String get noStockHere;

  /// No description provided for @noStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Declare no stock?'**
  String get noStockTitle;

  /// No description provided for @noStockBody.
  ///
  /// In en, this message translates to:
  /// **'BioBalance will record that this place starts empty. Stock arrives with restocks.'**
  String get noStockBody;

  /// No description provided for @toApprove.
  ///
  /// In en, this message translates to:
  /// **'To approve'**
  String get toApprove;

  /// No description provided for @attnStores.
  ///
  /// In en, this message translates to:
  /// **'Stores waiting'**
  String get attnStores;

  /// No description provided for @attnGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups waiting'**
  String get attnGroups;

  /// No description provided for @attnMembers.
  ///
  /// In en, this message translates to:
  /// **'Team members waiting'**
  String get attnMembers;

  /// No description provided for @attnStockCounts.
  ///
  /// In en, this message translates to:
  /// **'Stock counts to check'**
  String get attnStockCounts;

  /// No description provided for @attnReceipts.
  ///
  /// In en, this message translates to:
  /// **'Deliveries to check'**
  String get attnReceipts;

  /// No description provided for @attnRestockRequests.
  ///
  /// In en, this message translates to:
  /// **'Restock requests'**
  String get attnRestockRequests;

  /// No description provided for @stockSection.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stockSection;

  /// No description provided for @restocksSection.
  ///
  /// In en, this message translates to:
  /// **'Restocks'**
  String get restocksSection;

  /// No description provided for @paymentsSection.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get paymentsSection;

  /// No description provided for @runningLow.
  ///
  /// In en, this message translates to:
  /// **'Running low'**
  String get runningLow;

  /// No description provided for @orderNow.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get orderNow;

  /// No description provided for @orderQuantity.
  ///
  /// In en, this message translates to:
  /// **'How many to order?'**
  String get orderQuantity;

  /// No description provided for @sendOrder.
  ///
  /// In en, this message translates to:
  /// **'Send the order'**
  String get sendOrder;

  /// No description provided for @orderSent.
  ///
  /// In en, this message translates to:
  /// **'Order sent to BioBalance'**
  String get orderSent;

  /// No description provided for @bestStores.
  ///
  /// In en, this message translates to:
  /// **'Best stores, 30 days'**
  String get bestStores;

  /// No description provided for @bestGroups.
  ///
  /// In en, this message translates to:
  /// **'Best groups, 30 days'**
  String get bestGroups;

  /// No description provided for @regionPageResponsable.
  ///
  /// In en, this message translates to:
  /// **'Responsable'**
  String get regionPageResponsable;

  /// No description provided for @regionGroups.
  ///
  /// In en, this message translates to:
  /// **'Groups'**
  String get regionGroups;

  /// No description provided for @regionStores.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get regionStores;

  /// No description provided for @regionGrossistes.
  ///
  /// In en, this message translates to:
  /// **'Grossistes'**
  String get regionGrossistes;

  /// No description provided for @regionNoResponsable.
  ///
  /// In en, this message translates to:
  /// **'No responsable yet'**
  String get regionNoResponsable;

  /// No description provided for @rewardsHow.
  ///
  /// In en, this message translates to:
  /// **'A product’s own rate always beats its family’s rate. Tap a family or a product to set a rate for a period.'**
  String get rewardsHow;

  /// No description provided for @noFamilyRate.
  ///
  /// In en, this message translates to:
  /// **'No family rate'**
  String get noFamilyRate;

  /// No description provided for @familyRate.
  ///
  /// In en, this message translates to:
  /// **'Family rate {amount}'**
  String familyRate(String amount);

  /// No description provided for @ownRate.
  ///
  /// In en, this message translates to:
  /// **'Own rate'**
  String get ownRate;

  /// No description provided for @followsFamily.
  ///
  /// In en, this message translates to:
  /// **'Follows the family rate'**
  String get followsFamily;

  /// No description provided for @noReward.
  ///
  /// In en, this message translates to:
  /// **'No reward set'**
  String get noReward;

  /// No description provided for @findByProduct.
  ///
  /// In en, this message translates to:
  /// **'Find a sale by product'**
  String get findByProduct;

  /// No description provided for @noSalesWithProduct.
  ///
  /// In en, this message translates to:
  /// **'No sale includes this product'**
  String get noSalesWithProduct;

  /// No description provided for @noSalesThisMonth.
  ///
  /// In en, this message translates to:
  /// **'No sales this month'**
  String get noSalesThisMonth;

  /// No description provided for @previousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get previousMonth;

  /// No description provided for @nextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get nextMonth;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @themeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get themeAuto;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @cancelInvitation.
  ///
  /// In en, this message translates to:
  /// **'Cancel the invitation'**
  String get cancelInvitation;

  /// No description provided for @cancelInvitationTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel the invitation of {name}?'**
  String cancelInvitationTitle(String name);

  /// No description provided for @cancelInvitationBody.
  ///
  /// In en, this message translates to:
  /// **'The code stops working and the email address becomes free again. You can invite someone else.'**
  String get cancelInvitationBody;

  /// No description provided for @invitationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Invitation cancelled'**
  String get invitationCancelled;

  /// No description provided for @photoAddAnother.
  ///
  /// In en, this message translates to:
  /// **'Add another'**
  String get photoAddAnother;

  /// No description provided for @photoCount.
  ///
  /// In en, this message translates to:
  /// **'{count} of {max} photos'**
  String photoCount(int count, int max);

  /// No description provided for @photosNeeded.
  ///
  /// In en, this message translates to:
  /// **'Add 1 to 5 photos.'**
  String get photosNeeded;

  /// No description provided for @statusWaitingResponsable.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the responsable'**
  String get statusWaitingResponsable;

  /// No description provided for @declarationWaitingResponsable.
  ///
  /// In en, this message translates to:
  /// **'Your count is waiting for the responsable’s check, then the admin.'**
  String get declarationWaitingResponsable;

  /// No description provided for @recountAsked2.
  ///
  /// In en, this message translates to:
  /// **'Recount requested: waiting for the admin to allow it.'**
  String get recountAsked2;

  /// No description provided for @recountAllowed.
  ///
  /// In en, this message translates to:
  /// **'The admin allowed a recount. Count again with the button below.'**
  String get recountAllowed;

  /// No description provided for @recountRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Ask to count again'**
  String get recountRequestTitle;

  /// No description provided for @recountRequestSend.
  ///
  /// In en, this message translates to:
  /// **'Send the request'**
  String get recountRequestSend;

  /// No description provided for @recountRequestHint.
  ///
  /// In en, this message translates to:
  /// **'Why? (for example, you bought stock elsewhere)'**
  String get recountRequestHint;

  /// No description provided for @recountRequested.
  ///
  /// In en, this message translates to:
  /// **'Request sent to the admin'**
  String get recountRequested;

  /// No description provided for @reviewHint.
  ///
  /// In en, this message translates to:
  /// **'Check the photos and the numbers. Sent to the admin, it still needs their approval.'**
  String get reviewHint;

  /// No description provided for @sentToAdmin.
  ///
  /// In en, this message translates to:
  /// **'Sent to the admin'**
  String get sentToAdmin;

  /// No description provided for @sendBack.
  ///
  /// In en, this message translates to:
  /// **'Send back'**
  String get sendBack;

  /// No description provided for @sentBack.
  ///
  /// In en, this message translates to:
  /// **'Sent back to the grossiste'**
  String get sentBack;

  /// No description provided for @countsToCheck.
  ///
  /// In en, this message translates to:
  /// **'Counts to check'**
  String get countsToCheck;

  /// No description provided for @nothingToCheck.
  ///
  /// In en, this message translates to:
  /// **'Nothing to check right now'**
  String get nothingToCheck;

  /// No description provided for @typeRecount.
  ///
  /// In en, this message translates to:
  /// **'Recount request'**
  String get typeRecount;

  /// No description provided for @attnRecounts.
  ///
  /// In en, this message translates to:
  /// **'Recount requests'**
  String get attnRecounts;

  /// No description provided for @attnGrossisteCounts.
  ///
  /// In en, this message translates to:
  /// **'Grossiste counts to check'**
  String get attnGrossisteCounts;

  /// No description provided for @approveRecountTitle.
  ///
  /// In en, this message translates to:
  /// **'Allow a recount?'**
  String get approveRecountTitle;

  /// No description provided for @allowRecount.
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get allowRecount;

  /// No description provided for @recountReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason given'**
  String get recountReasonLabel;

  /// No description provided for @grossisteHandledBy.
  ///
  /// In en, this message translates to:
  /// **'This grossiste is looked after by the responsable of the region: they check the stock counts and photos before the admin approves.'**
  String get grossisteHandledBy;

  /// No description provided for @outOfStockName.
  ///
  /// In en, this message translates to:
  /// **'{name} is out of stock'**
  String outOfStockName(String name);

  /// No description provided for @nothingInStock.
  ///
  /// In en, this message translates to:
  /// **'Nothing in stock'**
  String get nothingInStock;

  /// No description provided for @nothingInStockHint.
  ///
  /// In en, this message translates to:
  /// **'Ask your responsable to restock the store.'**
  String get nothingInStockHint;

  /// No description provided for @seeMore.
  ///
  /// In en, this message translates to:
  /// **'See more ({count})'**
  String seeMore(int count);

  /// No description provided for @seeLess.
  ///
  /// In en, this message translates to:
  /// **'See less'**
  String get seeLess;

  /// No description provided for @almostOutCount.
  ///
  /// In en, this message translates to:
  /// **'{count} almost out'**
  String almostOutCount(int count);

  /// No description provided for @outCount.
  ///
  /// In en, this message translates to:
  /// **'{count} out'**
  String outCount(int count);

  /// No description provided for @leftCount.
  ///
  /// In en, this message translates to:
  /// **'{count} left'**
  String leftCount(int count);

  /// No description provided for @newStoreButton.
  ///
  /// In en, this message translates to:
  /// **'New store'**
  String get newStoreButton;

  /// No description provided for @newGroupButton.
  ///
  /// In en, this message translates to:
  /// **'New group'**
  String get newGroupButton;

  /// No description provided for @newMemberButton.
  ///
  /// In en, this message translates to:
  /// **'New member'**
  String get newMemberButton;

  /// No description provided for @noStoresInGroup.
  ///
  /// In en, this message translates to:
  /// **'No store in this group yet'**
  String get noStoresInGroup;

  /// No description provided for @noStoresInGroupHint.
  ///
  /// In en, this message translates to:
  /// **'Choose this group when you create or edit a store.'**
  String get noStoresInGroupHint;

  /// No description provided for @pendingTab.
  ///
  /// In en, this message translates to:
  /// **'To decide'**
  String get pendingTab;

  /// No description provided for @historyTab.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get historyTab;

  /// No description provided for @adjustStock.
  ///
  /// In en, this message translates to:
  /// **'Adjust the stock'**
  String get adjustStock;

  /// No description provided for @adjustStockHint.
  ///
  /// In en, this message translates to:
  /// **'Set the real quantities. Every change is kept in the history with your reason.'**
  String get adjustStockHint;

  /// No description provided for @adjustReason.
  ///
  /// In en, this message translates to:
  /// **'Reason (required)'**
  String get adjustReason;

  /// No description provided for @stockAdjusted.
  ///
  /// In en, this message translates to:
  /// **'Stock corrected'**
  String get stockAdjusted;

  /// No description provided for @editDepot.
  ///
  /// In en, this message translates to:
  /// **'Edit the depot'**
  String get editDepot;

  /// No description provided for @grossisteLabel.
  ///
  /// In en, this message translates to:
  /// **'Grossiste'**
  String get grossisteLabel;
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
