import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Session credentials must not migrate to another iPhone through a backup.
abstract final class SessionStorage {
  // A new service name prevents the plugin's legacy accessibility fallback
  // from reading or updating an older, migratable Keychain item.
  static const secure = FlutterSecureStorage(
    iOptions: IOSOptions(
      accountName: 'tn.biobalance.session.v2',
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
    ),
  );

  static Future<void> prepare() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // Deliberately require fresh authentication for legacy installations.
      // The account-scoped SQLite drafts and outbox are left intact.
      await const FlutterSecureStorage().delete(key: 'session');
    }
  }
}
