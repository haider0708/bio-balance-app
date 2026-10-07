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
  String get accountCreated => 'Account created and invitation sent';

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
  String get activePdvs => 'Active PDVs';

  @override
  String get activity => 'Activity';

  @override
  String get add => 'Add';

  @override
  String get addLesson => 'Add a lesson';

  @override
  String get addMember => 'Add a member';

  @override
  String get addMemberFromPdv => 'Open a point of sale to add a team member.';

  @override
  String get addMemberHint =>
      'They can sign in once BioBalance approves them. They receive an email with a code.';

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
  String get address => 'Address';

  @override
  String get adjustQuantities => 'Adjust quantities';

  @override
  String get adjustQuantitiesHint =>
      'Change what will be sent before choosing who sends it.';

  @override
  String get all => 'All';

  @override
  String get allCaughtUp => 'Everything is up to date.';

  @override
  String get allRegions => 'All regions';

  @override
  String get amendAndApprove => 'Correct and approve';

  @override
  String get amendReceiptHint =>
      'Compare with the photo of the paper and correct a quantity if needed.';

  @override
  String get amendStockHint =>
      'Change a quantity if the photo shows something different.';

  @override
  String get amountPerUnit => 'Amount per unit sold';

  @override
  String get amountPerUnitHint => 'Example: 0.500';

  @override
  String get amountTnd => 'Amount';

  @override
  String get announcement => 'Announcement';

  @override
  String get announcementScheduled => 'Announcement scheduled';

  @override
  String get announcementSent => 'Announcement sent';

  @override
  String get announcementsTitle => 'Announcements';

  @override
  String get appName => 'BioBalance';

  @override
  String get appVersion => 'Version';

  @override
  String approvalGroups(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count groups',
      one: '1 group',
    );
    return '$_temp0';
  }

  @override
  String approvalMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count team members',
      one: '1 team member',
    );
    return '$_temp0';
  }

  @override
  String approvalPayouts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count payouts',
      one: '1 payout',
    );
    return '$_temp0';
  }

  @override
  String approvalPdvs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points of sale',
      one: '1 point of sale',
    );
    return '$_temp0';
  }

  @override
  String approvalReceipts(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count deliveries',
      one: '1 delivery',
    );
    return '$_temp0';
  }

  @override
  String approvalRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count restock requests',
      one: '1 restock request',
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
  String get approvalsTitle => 'Approvals';

  @override
  String get approve => 'Approve';

  @override
  String get approveAndInvite => 'Approve and send invitation';

  @override
  String get approveAsCounted => 'Approve as counted';

  @override
  String approveGroupTitle(String name) {
    return 'Approve the group “$name”?';
  }

  @override
  String get approved => 'Approved';

  @override
  String get askRecount => 'Ask to count again';

  @override
  String get assignToGrossiste => 'Assign to a grossiste';

  @override
  String get auditTitle => 'History of changes';

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
  String get balanceShort => 'Balance';

  @override
  String get barcode => 'Barcode';

  @override
  String get barcodeUnknown => 'This barcode is not in the catalog.';

  @override
  String get byDay => 'day';

  @override
  String get byFamily => 'By family';

  @override
  String byName(String name) {
    return 'by $name';
  }

  @override
  String get byPdv => 'point of sale';

  @override
  String get byProduct => 'By product';

  @override
  String get byProductShort => 'product';

  @override
  String get byRegion => 'region';

  @override
  String get bySeller => 'seller';

  @override
  String get call => 'Call';

  @override
  String get cameraUnavailable =>
      'The camera is not available. Check the permission in your phone settings.';

  @override
  String get cancel => 'Cancel';

  @override
  String get cancelReason => 'Reason for cancelling';

  @override
  String get cancelReasonHint => 'Why is it cancelled?';

  @override
  String get cancelRequest => 'Cancel request';

  @override
  String get cancelRestock => 'Cancel the restock';

  @override
  String get cancelRule => 'Cancel this value';

  @override
  String get cancelRuleBody =>
      'Sales already made keep what they earned. Future sales will not earn it.';

  @override
  String get cancelRuleTitle => 'Cancel this value?';

  @override
  String get cancelSale => 'Cancel the sale';

  @override
  String get cancelSaleBody =>
      'The stock is put back and the reward is taken off your wallet.';

  @override
  String get cancelSaleTitle => 'Cancel this sale?';

  @override
  String get catalogTitle => 'Catalog';

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
  String get changeReceiver => 'Change who counts the goods';

  @override
  String get chooseAudience => 'Choose who receives it';

  @override
  String get chooseGrossiste => 'Choose a grossiste';

  @override
  String get choosePdvs => 'Choose points of sale';

  @override
  String get chooseProduct => 'Choose a product';

  @override
  String get chooseReceiver => 'Choose who counts the goods';

  @override
  String get city => 'City';

  @override
  String get close => 'Close';

  @override
  String get codeInvalid => 'Enter a valid code.';

  @override
  String get colApproved => 'Final';

  @override
  String get colReceived => 'Counted';

  @override
  String get colRequested => 'Asked';

  @override
  String get colShipped => 'Sent';

  @override
  String get completed => 'Completed';

  @override
  String get confirm => 'Confirm';

  @override
  String get confirmDelivery => 'Confirm the delivery';

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
  String get countedProducts => 'Counted products';

  @override
  String get counting => 'Counting…';

  @override
  String get courseAudienceHint => 'Leave empty to show it to everyone.';

  @override
  String get courseDeleted => 'Course deleted';

  @override
  String get courseIsDraft => 'Course unpublished';

  @override
  String get courseIsPublished => 'Course published';

  @override
  String get courseSummary => 'Short description';

  @override
  String get courseTitle => 'Course title';

  @override
  String get create => 'Create';

  @override
  String get createAndInvite => 'Create and send invitation';

  @override
  String get createPdv => 'Create the point of sale';

  @override
  String get current => 'Current';

  @override
  String get currentPassword => 'Current password';

  @override
  String get customPeriod => 'Choose dates';

  @override
  String get date => 'Date';

  @override
  String dateRange(String from, String to) {
    return '$from → $to';
  }

  @override
  String get deactivate => 'Deactivate';

  @override
  String get deactivateBody =>
      'They will be signed out and will no longer have access.';

  @override
  String deactivateTitle(String name) {
    return 'Deactivate $name?';
  }

  @override
  String get deactivated => 'Deactivated';

  @override
  String get decision => 'Decision';

  @override
  String get declaration => 'Stock declaration';

  @override
  String get declarationRejectedRetry =>
      'Your last stock declaration was rejected. Declare it again.';

  @override
  String get declarationSent => 'Sent to BioBalance for approval';

  @override
  String get declarationWaiting =>
      'A stock declaration is waiting for approval.';

  @override
  String get declarations => 'Declarations';

  @override
  String get declareFirstHint =>
      'Count every product you hold, add the quantities and take a photo of the stock. BioBalance checks it, then the stock becomes official.';

  @override
  String get declareStock => 'Declare the stock';

  @override
  String declaredQuantity(int count) {
    return 'Declared: $count';
  }

  @override
  String get decline => 'Decline';

  @override
  String get declinePayoutTitle => 'Why decline this payout?';

  @override
  String get decrease => 'Decrease';

  @override
  String get delete => 'Delete';

  @override
  String get deleteCourse => 'Delete the course';

  @override
  String get deleteCourseBody =>
      'Its lessons and everyone’s progress are deleted.';

  @override
  String get deleteCourseTitle => 'Delete this course?';

  @override
  String get deleteLessonTitle => 'Delete this lesson?';

  @override
  String get deliverTo => 'Deliver to';

  @override
  String deliveriesToConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count deliveries to confirm',
      one: '1 delivery to confirm',
    );
    return '$_temp0';
  }

  @override
  String get deliveriesToConfirmHint =>
      'Photograph the paper and count the goods.';

  @override
  String get deliveryPaper => 'Delivery paper';

  @override
  String get deliverySent => 'Sent to BioBalance for approval';

  @override
  String get depotName => 'Depot name';

  @override
  String get description => 'Description';

  @override
  String get discard => 'Discard';

  @override
  String get done => 'Done';

  @override
  String get draft => 'Draft';

  @override
  String get durationMinutes => 'Minutes';

  @override
  String get earnedToday => 'Earned today';

  @override
  String get edit => 'Edit';

  @override
  String get editCourse => 'Edit course';

  @override
  String get editLesson => 'Edit lesson';

  @override
  String get editPdv => 'Edit point of sale';

  @override
  String get editProduct => 'Edit product';

  @override
  String get editProfile => 'Edit my profile';

  @override
  String get email => 'Email';

  @override
  String get emailInvalid => 'Enter a valid email address.';

  @override
  String endsOn(String date) {
    return 'Ends $date';
  }

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
  String get everyone => 'Everyone';

  @override
  String get exportCsv => 'Export to a spreadsheet';

  @override
  String get family => 'Family';

  @override
  String get familyHint => 'Rewards can be set per family.';

  @override
  String get fieldRequired => 'Required';

  @override
  String get fileAttached => 'File attached';

  @override
  String get filterDone => 'Completed';

  @override
  String get filterOpen => 'In progress';

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
  String fromDate(String date) {
    return 'From $date';
  }

  @override
  String get fullName => 'Full name';

  @override
  String get fullNameOptional => 'Your name (optional)';

  @override
  String get grossisteDeclareFirst =>
      'Declare your depot stock with a photo so BioBalance can approve it.';

  @override
  String get grossistesTitle => 'Grossistes';

  @override
  String get group => 'Group';

  @override
  String get groupCreated => 'Group created. It is waiting for approval.';

  @override
  String get groupName => 'Group name';

  @override
  String get groupedBy => 'By';

  @override
  String get haveCode => 'I already have a code';

  @override
  String helloName(String name) {
    return 'Hello, $name';
  }

  @override
  String get history => 'History';

  @override
  String get howToUse => 'How to use';

  @override
  String get inRegions => 'In these regions';

  @override
  String get inactive => 'Inactive';

  @override
  String get increase => 'Increase';

  @override
  String get ingredients => 'Ingredients';

  @override
  String get initialStock => 'Opening stock';

  @override
  String get invitationResent => 'Invitation sent again';

  @override
  String get invitationSent => 'Invitation sent';

  @override
  String get invitedHint =>
      'Your account was approved and you received a code by email?';

  @override
  String get kind => 'Type';

  @override
  String get language => 'Language';

  @override
  String get last7Days => 'Last 7 days';

  @override
  String get lastMonth => 'Last month';

  @override
  String get latestSales => 'Latest sales';

  @override
  String get lessonArticle => 'Reading';

  @override
  String get lessonPdf => 'Document';

  @override
  String get lessonText => 'Text of the lesson';

  @override
  String get lessonTitle => 'Lesson title';

  @override
  String get lessonVideo => 'Video';

  @override
  String get lessons => 'Lessons';

  @override
  String lessonsDone(int done, int total) {
    return '$done of $total lessons';
  }

  @override
  String get lowStock => 'Products almost out';

  @override
  String get manageTraining => 'Manage courses';

  @override
  String get markAllRead => 'Mark all read';

  @override
  String get markAsPaid => 'Mark as paid';

  @override
  String markAsPaidHint(String amount) {
    return 'Confirm you paid $amount. It leaves their wallet.';
  }

  @override
  String get markDone => 'Mark as done';

  @override
  String get markNotDone => 'Mark as not done';

  @override
  String get markShipped => 'Mark as shipped';

  @override
  String get me => 'Me';

  @override
  String get memberAdded => 'Member added. Waiting for approval.';

  @override
  String get message => 'Message';

  @override
  String minutes(int count) {
    return '$count min';
  }

  @override
  String get more => 'More';

  @override
  String get moreTitle => 'More';

  @override
  String myRegion(String name) {
    return 'Region $name';
  }

  @override
  String myRestockRequests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count of your restock requests are in progress',
      one: '1 of your restock requests is in progress',
      zero: 'No restock request in progress',
    );
    return '$_temp0';
  }

  @override
  String get needsAttention => 'Needs attention';

  @override
  String get negativeStock => 'Products below zero';

  @override
  String get networkTitle => 'Network';

  @override
  String get newAccount => 'New account';

  @override
  String get newAccountHint =>
      'The person receives an email with a code to choose their password.';

  @override
  String get newAnnouncement => 'New announcement';

  @override
  String get newCourse => 'New course';

  @override
  String get newGroup => 'New group';

  @override
  String get newPassword => 'New password';

  @override
  String get newPdv => 'New point of sale';

  @override
  String get newPdvHint =>
      'It can be used right away for setup. BioBalance approves it before it sells.';

  @override
  String get newProduct => 'New product';

  @override
  String get newSale => 'New sale';

  @override
  String get next => 'Next';

  @override
  String get noActivePdv =>
      'You need an approved point of sale to request a restock.';

  @override
  String get noActivityYet => 'No activity yet';

  @override
  String get noAnnouncements => 'No announcement yet';

  @override
  String get noAnnouncementsHint =>
      'Write to responsables, grossistes or teams.';

  @override
  String get noCourses => 'No course yet';

  @override
  String get noCoursesAdminHint =>
      'Create a course, add lessons, then publish it.';

  @override
  String get noCoursesHint => 'New courses will appear here.';

  @override
  String get noEndDate => 'No end date';

  @override
  String get noGrossisteShort => 'No grossiste yet';

  @override
  String get noGrossisteYet =>
      'No grossiste yet. Create an account for one first.';

  @override
  String get noGroup => 'No group';

  @override
  String get noGroups => 'No group yet';

  @override
  String get noGroupsHint =>
      'A group gathers several points of sale of the same owner.';

  @override
  String get noHistoryYet => 'Nothing recorded yet';

  @override
  String get noLessonsYet => 'No lesson yet. Add one to publish the course.';

  @override
  String get noNotifications => 'Nothing new';

  @override
  String get noNotificationsHint =>
      'Announcements and updates will appear here.';

  @override
  String get noOrdersToPrepare => 'No order to prepare';

  @override
  String get noPayoutRequests => 'No payout request';

  @override
  String get noPayoutsYet => 'No payout yet';

  @override
  String get noPdvs => 'No point of sale yet';

  @override
  String get noPdvsHint =>
      'Add your first point of sale with the button below.';

  @override
  String get noPeople => 'Nobody here yet';

  @override
  String get noProductsFound => 'No product found';

  @override
  String get noRestocks => 'No restock';

  @override
  String get noRestocksHint =>
      'Request products for a point of sale when it runs low.';

  @override
  String get noRewardsYet => 'No reward set yet';

  @override
  String get noRewardsYetHint =>
      'Choose a family or a product and an amount per unit sold.';

  @override
  String get noRulesHere => 'Nothing here';

  @override
  String get noSalesInPeriod => 'No sales in this period';

  @override
  String get noSalesYet => 'No sales yet';

  @override
  String get noSalesYetHint =>
      'Your sales and what they earned will appear here.';

  @override
  String get noStockYet => 'No stock yet';

  @override
  String get noStockYetHint =>
      'Count what you have, take a photo and send it to BioBalance.';

  @override
  String get noTeamYet => 'No team member yet.';

  @override
  String get noWalletsYet => 'No wallet yet';

  @override
  String get none => 'None';

  @override
  String get notReadYet => 'Not read yet';

  @override
  String get note => 'Note';

  @override
  String get nothingToApprove => 'Nothing to approve';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get openDocument => 'Open the document';

  @override
  String get openRestocks => 'Restocks in progress';

  @override
  String get openVideo => 'Watch the video';

  @override
  String get optional => 'optional';

  @override
  String get orVideoLink => 'Or a video link';

  @override
  String get ordersTitle => 'Orders';

  @override
  String ordersToPrepare(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count orders to prepare',
      one: '1 order to prepare',
    );
    return '$_temp0';
  }

  @override
  String overlapBody(String details) {
    return 'These days are already covered:\n$details\n\nReplace it with the new value?';
  }

  @override
  String get overlapTitle => 'Another value already applies';

  @override
  String get packageSize => 'Size';

  @override
  String paidOn(String date) {
    return 'Paid on $date';
  }

  @override
  String get password => 'Password';

  @override
  String get passwordChanged => 'Password changed. You can sign in.';

  @override
  String get passwordChangedShort => 'Password changed';

  @override
  String get passwordRequired => 'Enter your password.';

  @override
  String get passwordRule => 'At least 8 characters.';

  @override
  String get passwordTooShort => 'Use at least 8 characters.';

  @override
  String get passwordsDiffer => 'The passwords do not match.';

  @override
  String get past => 'Past';

  @override
  String get payoutApproved => 'Payout recorded';

  @override
  String get payoutExplain =>
      'The admin will pay you and confirm. The amount leaves your wallet once approved.';

  @override
  String get payoutPaid => 'Paid';

  @override
  String get payoutRequested => 'Payout requested';

  @override
  String get payoutRequests => 'Payout requests';

  @override
  String get payouts => 'Payouts';

  @override
  String get payoutsTitle => 'Payouts';

  @override
  String get paysToday => 'Pays today';

  @override
  String get paysTodayHint =>
      'What one unit sold pays today, product by product.';

  @override
  String pdvCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points of sale',
      one: '1 point of sale',
      zero: 'No point of sale',
    );
    return '$_temp0';
  }

  @override
  String get pdvCreated => 'Point of sale created. It is waiting for approval.';

  @override
  String get pdvName => 'Name of the point of sale';

  @override
  String get pdvNotActive =>
      'Your point of sale is waiting for approval. You can sell as soon as it is active.';

  @override
  String get pdvWaitingNotice =>
      'Waiting for BioBalance to approve. You can already add the team and declare the stock.';

  @override
  String pdvsChosen(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count points of sale chosen',
      one: '1 point of sale chosen',
    );
    return '$_temp0';
  }

  @override
  String pendingCount(int count) {
    return '$count waiting';
  }

  @override
  String pendingPayout(String amount) {
    return '$amount already requested';
  }

  @override
  String get people => 'People';

  @override
  String get perUnit => 'per unit';

  @override
  String get periods => 'Periods';

  @override
  String get phone => 'Phone';

  @override
  String get photo => 'Photo';

  @override
  String get photoChoose => 'Choose from gallery';

  @override
  String get photoHint => 'Tap to take a photo';

  @override
  String get photoOfPaper => 'Photo of the delivery paper';

  @override
  String get photoOfStock => 'Photo of the stock';

  @override
  String get photoReady => 'Photo ready';

  @override
  String get photoRequiredHint => 'Take the photo to send.';

  @override
  String get photoRetake => 'Retake';

  @override
  String get photoTake => 'Take a photo';

  @override
  String get photoUploading => 'Sending…';

  @override
  String get pinAnnouncement => 'Pin to the top';

  @override
  String get pinAnnouncementHint =>
      'It stays at the top of their notifications.';

  @override
  String get pinned => 'Pinned';

  @override
  String get pointOfSale => 'Point of sale';

  @override
  String get precautions => 'Precautions';

  @override
  String get prepareAndShip => 'Prepare and ship';

  @override
  String get productActive => 'Available';

  @override
  String get productActiveHint => 'Hidden from sales and orders when off.';

  @override
  String get productName => 'Product name';

  @override
  String get productPhoto => 'Product photo';

  @override
  String get products => 'Products';

  @override
  String get productsNeeded => 'Products needed';

  @override
  String get progress => 'Progress';

  @override
  String get progressByPerson => 'Progress by person';

  @override
  String get publish => 'Publish';

  @override
  String get published => 'Published';

  @override
  String get quantitiesAdjusted => 'Quantities adjusted';

  @override
  String get quantitiesReceived => 'Quantities received';

  @override
  String get quantity => 'Quantity';

  @override
  String quantityMax(int max) {
    return 'Up to $max';
  }

  @override
  String get reactivate => 'Reactivate';

  @override
  String get reactivated => 'Reactivated';

  @override
  String readAt(String date) {
    return 'Read $date';
  }

  @override
  String readOf(int read, int total) {
    return '$read of $total read';
  }

  @override
  String get reasonRequired => 'Reason (required)';

  @override
  String get receiveHint =>
      'Photograph the signed delivery paper and enter what you really received for each product.';

  @override
  String get receivedBy => 'Counted by';

  @override
  String get receiverSaved => 'Saved';

  @override
  String get recent => 'Recent';

  @override
  String get recipients => 'Recipients';

  @override
  String get recordSale => 'Record the sale';

  @override
  String get recount => 'Recount';

  @override
  String get recountAsked => 'Sent back for a new count';

  @override
  String get recountHint =>
      'The quantities below are what the system holds. Correct them to what you count, add a photo, and send.';

  @override
  String get recountReasonHint => 'What does not match the paper?';

  @override
  String get recountStock => 'Recount the stock';

  @override
  String get recoveryCode => 'Recovery code';

  @override
  String get reference => 'Reference';

  @override
  String get refresh => 'Refresh';

  @override
  String get region => 'Region';

  @override
  String regionOf(String name) {
    return 'Region $name';
  }

  @override
  String get regions => 'Regions';

  @override
  String get reject => 'Reject';

  @override
  String get rejectReasonHint => 'Explain what to fix so it can be sent again.';

  @override
  String get rejectReasonTitle => 'Why is it rejected?';

  @override
  String get rejected => 'Rejected';

  @override
  String get remove => 'Remove';

  @override
  String get replaceValue => 'Replace';

  @override
  String get reportsTitle => 'Reports';

  @override
  String get requestPayout => 'Request a payout';

  @override
  String get requestRestock => 'Request a restock';

  @override
  String get requestedBy => 'Requested by';

  @override
  String requestedInStock(int requested, int stock) {
    return 'Asked $requested · in stock $stock';
  }

  @override
  String requestedQuantity(int count) {
    return 'Requested: $count';
  }

  @override
  String get resendInvitation => 'Send the invitation again';

  @override
  String get resetCodeSent => 'If the account exists, a code was sent.';

  @override
  String get restock => 'Restock';

  @override
  String get restockApproved => 'Restock approved. The stock is updated.';

  @override
  String get restockAssigned => 'With the grossiste';

  @override
  String get restockCancelled => 'Restock cancelled';

  @override
  String get restockCompleted => 'Completed';

  @override
  String get restockReceived => 'To approve';

  @override
  String get restockRequested => 'Requested';

  @override
  String get restockRouted => 'The order was sent on';

  @override
  String get restockSent => 'Request sent';

  @override
  String get restockShipped => 'On its way';

  @override
  String get restockShippedMessage => 'Marked as shipped';

  @override
  String get restocksTitle => 'Restocks';

  @override
  String get resubmit => 'Submit again';

  @override
  String get resubmitted => 'Submitted again';

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
  String get rewardSaved => 'Reward saved';

  @override
  String get rewardsMonth => 'Rewards, 30 days';

  @override
  String get rewardsTitle => 'Rewards';

  @override
  String get roleAdmin => 'Administrator';

  @override
  String get roleGrossiste => 'Grossiste';

  @override
  String get roleGrossistePlural => 'Grossistes';

  @override
  String get roleResponsable => 'Responsable';

  @override
  String get roleResponsablePlural => 'Responsables';

  @override
  String get roleVendeur => 'Team member';

  @override
  String get roleVendeurPlural => 'Team members';

  @override
  String get roleVendeurShort => 'Team member';

  @override
  String get ruleCancelled => 'Value cancelled';

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
  String get salesLast14Days => 'Units sold, last 14 days';

  @override
  String get salesTitle => 'My sales';

  @override
  String get salesTitleShort => 'Sales';

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
  String get saveReward => 'Save the reward';

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
  String get schedule => 'Schedule';

  @override
  String get scheduleTitle => 'Schedule this announcement?';

  @override
  String get scheduled => 'Scheduled';

  @override
  String scheduledFor(String date) {
    return 'Scheduled for $date';
  }

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
  String get sendForApproval => 'Send for approval';

  @override
  String get sendFromBiobalance => 'Send from BioBalance';

  @override
  String get sendNow => 'Send now';

  @override
  String get sendNowOption => 'Send now';

  @override
  String sendNowTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people',
      one: '1 person',
    );
    return 'Send to $_temp0?';
  }

  @override
  String get sendRequest => 'Send the request';

  @override
  String get sendToAdmin => 'Send to BioBalance';

  @override
  String get sentBy => 'Sent by';

  @override
  String get sentFrom => 'Sent from';

  @override
  String get server => 'Server';

  @override
  String get setReward => 'Set a reward';

  @override
  String get settingsTitle => 'Settings';

  @override
  String shipHint(String destination) {
    return 'Enter what leaves your depot for $destination.';
  }

  @override
  String shippedReceived(int shipped, int received) {
    return 'Sent $shipped · counted $received';
  }

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
  String startsOn(String date) {
    return 'Starts $date';
  }

  @override
  String get statusActive => 'Active';

  @override
  String get statusApproved => 'Approved';

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusPending => 'Pending';

  @override
  String get statusRejected => 'Rejected';

  @override
  String get statusSuspended => 'Suspended';

  @override
  String get statusWaitingApproval => 'Waiting for approval';

  @override
  String get stockAllGood => 'All stock levels are fine';

  @override
  String get stockApproved => 'Stock approved';

  @override
  String get stockApprovedLong => 'Stock approved: see quantities';

  @override
  String get stockLevels => 'Quantities';

  @override
  String get stockLow => 'Low';

  @override
  String get stockMissing => 'No stock yet';

  @override
  String get stockMissingLong => 'Declare the opening stock with a photo';

  @override
  String get stockNegative => 'Below zero';

  @override
  String get stockRejected => 'Stock rejected';

  @override
  String get stockRejectedLong => 'Stock rejected: declare it again';

  @override
  String get stockTitle => 'Stock';

  @override
  String get stockWaiting => 'Stock waiting';

  @override
  String get stockWaitingLong => 'Stock waiting for approval';

  @override
  String get suspend => 'Suspend';

  @override
  String get suspendPdvBody =>
      'Its team can no longer sell until it is reactivated.';

  @override
  String suspendTitle(String name) {
    return 'Suspend $name?';
  }

  @override
  String get suspended => 'Suspended';

  @override
  String get system => 'System';

  @override
  String get tabApprovals => 'Approvals';

  @override
  String get tabGroups => 'Groups';

  @override
  String get tabHome => 'Home';

  @override
  String get tabLearn => 'Learn';

  @override
  String get tabNetwork => 'Network';

  @override
  String get tabOrders => 'Orders';

  @override
  String get tabPdvs => 'Stores';

  @override
  String get tabPeople => 'People';

  @override
  String get tabReports => 'Reports';

  @override
  String get tabRestocks => 'Restocks';

  @override
  String get tabSales => 'Sales';

  @override
  String get tabWallet => 'Wallet';

  @override
  String get team => 'Team';

  @override
  String teamCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count members',
      one: '1 member',
      zero: 'No team',
    );
    return '$_temp0';
  }

  @override
  String get thisMonth => 'This month';

  @override
  String get thisWeek => 'This week';

  @override
  String get title => 'Title';

  @override
  String get toPay => 'To pay';

  @override
  String get today => 'Today';

  @override
  String get topPdvs => 'Top points of sale, 30 days';

  @override
  String get topProducts => 'Top products, 30 days';

  @override
  String get torch => 'Flashlight';

  @override
  String get totalUnits => 'Total units';

  @override
  String get trainingTitle => 'Training';

  @override
  String trendSemantics(int total) {
    return 'Chart: $total units sold over the last 14 days';
  }

  @override
  String get typeGroup => 'Group';

  @override
  String get typeMember => 'Team member';

  @override
  String get typePayout => 'Payout';

  @override
  String get typePdv => 'Point of sale';

  @override
  String get typeReceipt => 'Delivery';

  @override
  String get typeRestockRequest => 'Restock request';

  @override
  String get typeStock => 'Stock';

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
  String get unpublish => 'Unpublish';

  @override
  String get upcoming => 'Upcoming';

  @override
  String get uploadPdf => 'Upload a PDF';

  @override
  String get uploadVideo => 'Upload a video (MP4)';

  @override
  String get videoUnavailable => 'This video cannot be played.';

  @override
  String get viewSales => 'View sales';

  @override
  String waitingAdmin(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items are waiting for BioBalance to approve',
      one: '1 item is waiting for BioBalance to approve',
    );
    return '$_temp0';
  }

  @override
  String waitingForYou(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items are waiting for you',
      one: '1 item is waiting for you',
    );
    return '$_temp0';
  }

  @override
  String get waitingToSend => 'Waiting to be sent';

  @override
  String get walletBalance => 'Wallet balance';

  @override
  String walletSummaryLine(String earned, String paid) {
    return 'Earned $earned · paid $paid';
  }

  @override
  String get walletTitle => 'Wallet';

  @override
  String get wallets => 'Wallets';

  @override
  String get whoCountsHint =>
      'They will photograph the paper and enter the quantities.';

  @override
  String get whoCountsTheGoods => 'Who counts the goods?';

  @override
  String get whoIsItFor => 'Who is it for?';

  @override
  String get wholeNetwork => 'Whole network';

  @override
  String willReach(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count people will receive it',
      one: '1 person will receive it',
      zero: 'Nobody would receive it',
    );
    return '$_temp0';
  }

  @override
  String get withdrawAnnouncement => 'Withdraw the announcement';

  @override
  String get withdrawBody => 'It has not been sent yet and will not go out.';

  @override
  String get withdrawTitle => 'Withdraw this announcement?';

  @override
  String get withdrawn => 'Announcement withdrawn';

  @override
  String get yesterday => 'Yesterday';

  @override
  String get youEarned => 'You earned';

  @override
  String get paste => 'Paste';

  @override
  String get chooseStoreForMember => 'Which store is this person joining?';

  @override
  String inStockCount(int count) {
    return '$count in stock';
  }

  @override
  String get outOfStock => 'Out of stock';

  @override
  String get noStockHere => 'This store has no stock yet';

  @override
  String get noStockTitle => 'Declare no stock?';

  @override
  String get noStockBody =>
      'BioBalance will record that this place starts empty. Stock arrives with restocks.';

  @override
  String get toApprove => 'To approve';

  @override
  String get attnStores => 'Stores waiting';

  @override
  String get attnGroups => 'Groups waiting';

  @override
  String get attnMembers => 'Team members waiting';

  @override
  String get attnStockCounts => 'Stock counts to check';

  @override
  String get attnReceipts => 'Deliveries to check';

  @override
  String get attnRestockRequests => 'Restock requests';

  @override
  String get stockSection => 'Stock';

  @override
  String get restocksSection => 'Restocks';

  @override
  String get paymentsSection => 'Payments';

  @override
  String get runningLow => 'Running low';

  @override
  String get orderNow => 'Order';

  @override
  String get orderQuantity => 'How many to order?';

  @override
  String get sendOrder => 'Send the order';

  @override
  String get orderSent => 'Order sent to BioBalance';

  @override
  String get bestStores => 'Best stores, 30 days';

  @override
  String get bestGroups => 'Best groups, 30 days';

  @override
  String get regionPageResponsable => 'Responsable';

  @override
  String get regionGroups => 'Groups';

  @override
  String get regionStores => 'Stores';

  @override
  String get regionGrossistes => 'Grossistes';

  @override
  String get regionNoResponsable => 'No responsable yet';

  @override
  String get rewardsHow =>
      'A product’s own rate always beats its family’s rate. Tap a family or a product to set a rate for a period.';

  @override
  String get noFamilyRate => 'No family rate';

  @override
  String familyRate(String amount) {
    return 'Family rate $amount';
  }

  @override
  String get ownRate => 'Own rate';

  @override
  String get followsFamily => 'Follows the family rate';

  @override
  String get noReward => 'No reward set';

  @override
  String get findByProduct => 'Find a sale by product';

  @override
  String get noSalesWithProduct => 'No sale includes this product';

  @override
  String get noSalesThisMonth => 'No sales this month';

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get appearance => 'Appearance';

  @override
  String get themeAuto => 'Auto';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';
}
