import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the sign-in is kept: on this phone only, and on an iPhone readable once the phone was
/// unlocked after a restart, since the background alert check runs while the phone is locked.
const secureStorage = FlutterSecureStorage(
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);
