import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Chooses [dayMonthYear] (JJ/MM/AAAA) in the calendar opened by [field], through the
/// picker's own keyboard entry so the test does not depend on the visible month.
Future<void> pickDate(WidgetTester t, Finder field, String dayMonthYear) async {
  await t.ensureVisible(field);
  await t.tap(field);
  await t.pumpAndSettle();
  await t.tap(find.byIcon(Icons.edit_outlined));
  await t.pumpAndSettle();
  final entry = find.byType(TextField).last;
  final hint = t.widget<TextField>(entry).decoration?.hintText ?? '';
  final parts = dayMonthYear.split('/');
  // The picker reads day-first or month-first depending on the app's language.
  final text = hint.toLowerCase().startsWith('m')
      ? '${parts[1]}/${parts[0]}/${parts[2]}'
      : dayMonthYear;
  await t.enterText(entry, text);
  await t.pumpAndSettle();
  await t.tap(find.text('Choisir'));
  await t.pumpAndSettle();
}
