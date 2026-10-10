// Drafts: kept per account, forgotten when too old or when the account goes, and the
// quantities of a count put back exactly.
import 'package:biobalance/core/drafts/drafts.dart';
import 'package:biobalance/core/widgets/quantity_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a draft belongs to one account and expires', () async {
    final prefs = await SharedPreferences.getInstance();
    await Drafts.write(prefs, 'u1', 'sale', {
      'cart': {'a': 2},
    });
    expect(Drafts.read(prefs, 'u1', 'sale', life: const Duration(hours: 1)), {
      'cart': {'a': 2},
    });
    expect(
      Drafts.read(prefs, 'u2', 'sale', life: const Duration(hours: 1)),
      isNull,
    );
    // Too old: gone, and removed from the phone.
    expect(Drafts.read(prefs, 'u1', 'sale', life: Duration.zero), isNull);
    expect(prefs.getKeys(), isEmpty);
  });

  test(
    'a damaged draft is dropped, and deleting an account forgets its drafts',
    () async {
      SharedPreferences.setMockInitialValues({
        'draft.u1.sale': 'not json',
        'draft.u1.count.p1': '{"at":"2026-10-11T09:00:00.000","data":{}}',
        'draft.u2.sale': '{"at":"2026-10-11T09:00:00.000","data":{}}',
        'app.locale': 'fr',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        Drafts.read(prefs, 'u1', 'sale', life: const Duration(days: 9999)),
        isNull,
      );
      await Drafts.forget(prefs, 'u1');
      expect(prefs.getKeys(), {'draft.u2.sale', 'app.locale'});
    },
  );

  test('a count is put back over what the place holds, and can start over', () {
    QuantityItem held(String id, int quantity) =>
        QuantityItem(productId: id, name: id, family: 'F', quantity: quantity);
    final controller = QuantityController()
      ..addItem(held('a', 4))
      ..addItem(held('b', 1));
    expect(controller.edited, isFalse);
    controller.restore([
      {'productId': 'a', 'quantity': 7, 'name': 'a', 'family': 'F'},
      {'productId': 'c', 'quantity': 2, 'name': 'Cream', 'family': 'Care'},
      {'productId': 3, 'quantity': 'x'},
    ]);
    expect(controller.edited, isTrue);
    expect(controller.lines(), [
      {'productId': 'a', 'quantity': 7},
      {'productId': 'b', 'quantity': 1},
      {'productId': 'c', 'quantity': 2},
    ]);
    expect(controller.toDraft().last['name'], 'Cream');
    controller.reset([held('a', 4)]);
    expect(controller.edited, isFalse);
    expect(controller.lines(), [
      {'productId': 'a', 'quantity': 4},
    ]);
  });
}
