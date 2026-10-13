// French counts zero as singular: a "=1" wording is used for 0 as well, so it must show the
// number instead of writing "1" (or nothing waiting reads "1 élément vous attend").
import 'dart:convert';
import 'dart:io';

import 'package:biobalance/l10n/app_localizations_fr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zero is written as zero in French', () {
    final t = AppLocalizationsFr();
    expect(t.units(0), '0 unité');
    expect(t.units(1), '1 unité');
    expect(t.units(3), '3 unités');
    expect(t.waitingForYou(0), '0 élément vous attend');
    expect(t.salesCount(0), 'Aucune vente');
  });

  test('no French singular wording writes the number 1 itself', () {
    final messages = jsonDecode(
      File('lib/l10n/app_fr.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    final literalOne = RegExp(r'(=1|one)\{[^{}]*\b1\b');
    final wrong = [
      for (final entry in messages.entries)
        if (entry.value is String &&
            !(entry.value as String).contains('=0{') &&
            literalOne.hasMatch(entry.value as String))
          entry.key,
    ];
    expect(wrong, isEmpty);
  });
}
