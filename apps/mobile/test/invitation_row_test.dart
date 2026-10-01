import 'package:biobalance/domain/models/invitation.dart';
import 'package:biobalance/ui/features/team/invitations_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Invitation invitation(String status) => Invitation.fromJson({
  'id': 'invite-$status',
  'email': '$status@example.test',
  'kind': 'responsible',
  'status': status,
  'storeIds': <String>[],
  'version': 1,
  'expiresAt': '2026-10-05T10:00:00Z',
  'acceptedAt': status == 'accepted' ? '2026-10-02T09:00:00Z' : null,
});

Future<List<String>> pump(WidgetTester tester, String status) async {
  final actions = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: InvitationRow(
            item: invitation(status),
            stores: const [],
            busy: false,
            onAction: actions.add,
          ),
        ),
      ),
    ),
  );
  return actions;
}

void main() {
  testWidgets('a pending invitation can be resent, disabled or deleted', (
    t,
  ) async {
    final actions = await pump(t, 'pending');
    expect(find.text('En attente'), findsOneWidget);
    expect(find.text('Renvoyer'), findsOneWidget);
    expect(find.text('Désactiver'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);
    await t.tap(find.text('Renvoyer'));
    await t.tap(find.text('Désactiver'));
    await t.tap(find.text('Supprimer'));
    expect(actions, ['resend', 'revoke', 'archive']);
  });

  testWidgets('an expired invitation is relaunched, not disabled', (t) async {
    await pump(t, 'expired');
    expect(find.text('Expirée'), findsOneWidget);
    expect(find.text('Relancer'), findsOneWidget);
    expect(find.text('Désactiver'), findsNothing);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('a disabled invitation can be relaunched or deleted', (t) async {
    await pump(t, 'revoked');
    expect(find.text('Désactivée'), findsOneWidget);
    expect(find.text('Relancer'), findsOneWidget);
    expect(find.text('Supprimer'), findsOneWidget);
  });

  testWidgets('a created account shows its date and offers nothing', (t) async {
    await pump(t, 'accepted');
    expect(find.text('Compte créé'), findsOneWidget);
    expect(find.textContaining('Compte créé le'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
  });
}
