import 'package:biobalance/core/auth/me.dart';
import 'package:biobalance/core/auth/session.dart';
import 'package:biobalance/core/theme/app_theme.dart';
import 'package:biobalance/features/network/network_models.dart';
import 'package:biobalance/features/network/region_moves.dart';
import 'package:biobalance/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'regions_test.dart' as r show info;
import 'screenshots_test.dart' as base show server;

Person person(String id, String name, String regionId) => Person(
  id: id,
  name: name,
  email: '$id@x.tn',
  role: Role.responsable,
  status: ItemStatus.active,
  activated: true,
  regionId: regionId,
);

void main() {
  testWidgets('moving a responsable into a taken region asks, then swaps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var swapped = false;
    final s = base.server('ADMIN')
      ..on('GET /v1/regions/overview', [
        r.info(
          'r1',
          'Nord',
          boss: {
            'id': 'u1',
            'name': 'Nora',
            'email': 'n@x.tn',
            'phone': null,
            'status': 'ACTIVE',
          },
        ),
        r.info(
          'r3',
          'Sud',
          boss: {
            'id': 'u3',
            'name': 'Sami',
            'email': 's@x.tn',
            'phone': null,
            'status': 'ACTIVE',
          },
        ),
      ])
      ..on('GET /v1/regions', [
        {'id': 'r1', 'code': 'NORD', 'name': 'Nord'},
        {'id': 'r3', 'code': 'SUD', 'name': 'Sud'},
      ])
      ..handle('POST /v1/users/u1/move', (request) {
        final data = request.data as Map;
        if (data['swap'] == true) {
          swapped = true;
          return (status: 201, body: {'ok': true});
        }
        return (
          status: 409,
          body: {'code': 'REGION_HAS_RESPONSABLE', 'message': 'taken'},
        );
      });
    final container = ProviderContainer(
      overrides: s.overrides(
        token: 'a-valid-token-of-sufficient-length-123456',
      ),
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(sessionProvider.future));
    late WidgetRef captured;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                captured = ref;
                return TextButton(
                  onPressed: () => moveResponsableTo(
                    context,
                    ref,
                    person('u1', 'Nora', 'r1'),
                    'r3',
                  ),
                  child: const Text('go'),
                );
              },
            ),
          ),
        ),
      ),
    );
    expect(captured, isNotNull);
    await tester.tap(find.text('go'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // Nothing moved yet: the admin is asked first, with both names.
    expect(find.text('Swap the two responsables?'), findsOneWidget);
    expect(
      find.textContaining('Nora takes Sud, and Sami goes to Nord.'),
      findsOneWidget,
    );
    expect(swapped, isFalse);
    await tester.tap(find.text('Swap'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(swapped, isTrue);
  });
}
