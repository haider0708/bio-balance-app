import 'dart:ui' show Size;

// Announcements and training, for a visual review.
import 'package:flutter_test/flutter_test.dart';

import 'screenshots_test.dart' as base show loadFonts, server;
import 'support/harness.dart';

void main() {
  setUpAll(base.loadFonts);

  testWidgets('announcements and training screens', (tester) async {
    final now = DateTime.now();
    final s = base.server('ADMIN')
      ..on('GET /v1/messages', [
        {'id': 'm1', 'title': 'Nouveau tarif des sérums dès lundi', 'body': 'À partir de lundi, les sérums rapportent 0,800 TND par unité vendue.', 'pinned': true, 'status': 'SENT', 'recipientCount': 24, 'readCount': 17, 'createdAt': now.toIso8601String(), 'scheduledFor': null, 'sentAt': now.toIso8601String()},
        {'id': 'm2', 'title': 'Inventaire de fin de mois', 'body': 'Merci de compter vos stocks avant vendredi.', 'pinned': false, 'status': 'SCHEDULED', 'recipientCount': 9, 'readCount': 0, 'createdAt': now.toIso8601String(), 'scheduledFor': now.add(const Duration(days: 2)).toIso8601String(), 'sentAt': null},
      ])
      ..on('GET /v1/courses', [
        {'id': 'c1', 'title': 'Bien présenter les sérums', 'summary': 'Les gestes qui font vendre en pharmacie.', 'coverId': null, 'status': 'PUBLISHED', 'lessonCount': 5, 'completedCount': 3, 'minutes': 25, 'audience': {'roles': <String>[], 'regionIds': <String>[]}},
        {'id': 'c2', 'title': 'Conseils capillaires', 'summary': 'Choisir le bon shampoing.', 'coverId': null, 'status': 'DRAFT', 'lessonCount': 2, 'completedCount': 0, 'minutes': 10, 'audience': {'roles': ['VENDEUR'], 'regionIds': <String>[]}},
      ]);
    await launch(tester, s, language: 'en', size: const Size(412, 1100));
    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.tap(find.text('Announcements'));
    await settle(tester);
    await screenshot(tester, '50-announcements');
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Training'));
    await settle(tester);
    await screenshot(tester, '51-training-admin');
  });
}
