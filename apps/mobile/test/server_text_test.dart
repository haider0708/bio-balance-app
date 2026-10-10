// The phone and the server word notifications the same way: the server needs the words for
// iPhone push alerts, the app shows them in its inbox and background alerts.
import 'dart:convert';
import 'dart:io';

import 'package:biobalance/core/l10n/server_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the server has the same notification wording as the app', () {
    final server =
        (jsonDecode(
          File('../api/src/core/notice-text.json').readAsStringSync(),
        ) as Map<String, dynamic>).map((key, value) {
          final text = value as Map<String, dynamic>;
          return MapEntry(key, (text['en'] as String, text['fr'] as String));
        });
    expect(server, ServerText.notificationTexts);
  });

  test('a note already in the wording is not added twice', () {
    expect(
      ServerText.notification('fr', 'stock.adjusted', {
        'place': 'Para Lac',
        'note': 'recompté',
      }),
      'Le stock de Para Lac a été corrigé : recompté',
    );
    expect(
      ServerText.notification('en', 'restock.cancelled', {
        'number': 'R-1',
        'note': 'duplicate',
      }),
      'Restock R-1 was cancelled. — duplicate',
    );
  });
}
