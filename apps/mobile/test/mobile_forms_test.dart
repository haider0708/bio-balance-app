import 'dart:async';

import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/core/forms.dart';
import 'package:biobalance/ui/core/option_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'save stays reachable above keyboard, prevents double submit and retains failed input',
    (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var calls = 0;
      final pending = Completer<void>();
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: EditorScreen(
            title: 'Configurer le magasin',
            fields: [
              for (var i = 0; i < 12; i++)
                FieldSpec('f$i', 'Valeur $i', initial: 'Valeur conservée $i'),
            ],
            submit: (values) async {
              calls++;
              expect(values['f0'], 'Ma valeur');
              await pending.future;
            },
          ),
        ),
      );
      await t.enterText(find.byKey(const ValueKey('field.f0')), 'Ma valeur');
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pump();
      final save = find.byKey(const ValueKey('editor.save'));
      expect(t.getBottomRight(save).dy, lessThanOrEqualTo(500));
      ScaffoldMessenger.of(t.element(find.byType(EditorScreen))).showSnackBar(
        const SnackBar(content: Text('Une alerte de stock est disponible.')),
      );
      await t.pump(const Duration(milliseconds: 300));
      expect(save.hitTestable(), findsOneWidget);
      await t.tap(save);
      await t.pump();
      await t.tap(save);
      await t.pump();
      expect(calls, 1);
      pending.completeError(Exception('offline'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('field.f0')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('field.f0')))
            .controller!
            .text,
        'Ma valeur',
      );
      expect(t.widget<FilledButton>(save).onPressed, isNotNull);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'keyboard Next advances one field and validation reveals the missing field',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          home: EditorScreen(
            title: 'Paramètres',
            fields: [
              for (var i = 0; i < 12; i++) FieldSpec('f$i', 'Valeur $i'),
            ],
            submit: (_) async => fail('Invalid form must not submit'),
          ),
        ),
      );
      await t.enterText(find.byKey(const ValueKey('field.f0')), 'première');
      await t.testTextInput.receiveAction(TextInputAction.next);
      await t.pump();
      final second = find.descendant(
        of: find.byKey(const ValueKey('field.f1')),
        matching: find.byType(EditableText),
      );
      expect(t.widget<EditableText>(second).focusNode.hasFocus, isTrue);
      FocusManager.instance.primaryFocus?.unfocus();
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('field.f11')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const ValueKey('editor.save')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('field.f1')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('Ce champ est requis.'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'restored choices update their label and remain searchable with large text and keyboard',
    (t) async {
      t.view.physicalSize = const Size(360, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final controller = TextEditingController();
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: OptionField(
                label: 'Produit',
                controller: controller,
                options: {for (var i = 0; i < 1000; i++) '$i': 'Produit $i'},
              ),
            ),
          ),
        ),
      );
      controller.text = '617';
      await t.pump();
      expect(find.text('Produit 617'), findsOneWidget);
      await t.tap(find.byType(OptionField));
      await t.pumpAndSettle();
      expect(find.byType(CompactRow).evaluate().length, lessThan(30));
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.enterText(find.byType(TextField), 'Produit 942');
      await t.pumpAndSettle();
      final choice = find.descendant(
        of: find.byType(CompactRow),
        matching: find.text('Produit 942'),
      );
      await Scrollable.ensureVisible(t.element(choice), alignment: .5);
      await t.pumpAndSettle();
      await t.tap(choice);
      await t.pumpAndSettle();
      expect(controller.text, '942');
      expect(find.text('Produit 942'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
