// Where a tapped alert leads, for each kind of thing and each role (docs/notifications.md).
import 'package:biobalance/core/auth/me.dart';
import 'package:biobalance/features/notifications/notifications_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every alert leads somewhere useful for the person who gets it', () {
    const id = 'x1';
    final cases = <(Role, String, String?)>[
      (Role.responsable, 'Sale', '/sales/x1'),
      (Role.vendeur, 'Sale', '/sales/x1'),
      (Role.vendeur, 'RewardRule', '/wallet'),
      (Role.vendeur, 'Course', '/training/x1'),
      (Role.responsable, 'Course', '/training/x1'),
      (Role.admin, 'Course', '/training/manage/x1'),
      (Role.responsable, 'Region', '/home'),
      (Role.admin, 'PayoutRequest', '/payouts'),
      (Role.vendeur, 'PayoutRequest', '/wallet'),
      (Role.responsable, 'RestockOrder', '/restocks/x1'),
      (Role.admin, 'User', '/approvals'),
    ];
    for (final (role, type, route) in cases) {
      expect(routeForEntity(role, type, id), route, reason: '$role $type');
    }
    // The network's evening summary has no record of its own: it opens the home screen.
    expect(routeForEntity(Role.admin, 'Network', null), '/home');
    expect(routeForEntity(Role.vendeur, null, null), isNull);
  });
}
