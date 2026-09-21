import 'dart:async';

import 'package:biobalance/ui/core/forms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'save completion during Back animation cannot pop the previous screen',
    (t) async {
      final saved = Completer<void>();
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => openEditor(
                  context,
                  title: 'Modifier',
                  fields: const [
                    FieldSpec('name', 'Nom', initial: 'Conserver'),
                  ],
                  submit: (_) async => saved.future,
                ),
                child: const Text('Accueil'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Accueil'));
      await t.pumpAndSettle();
      await t.tap(find.text('Enregistrer'));
      await t.pump();
      final editorContext = t.element(find.byType(EditorScreen));
      Navigator.of(editorContext).pop();
      saved.complete();
      await t.pumpAndSettle();
      expect(find.text('Accueil'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
