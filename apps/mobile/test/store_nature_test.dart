import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/domain/models/store_nature.dart';

import 'package:flutter_test/flutter_test.dart';

Json storeJson({Object? nature, bool includeNature = true}) => {
  'id': 'store-1',
  'organizationId': 'group-1',
  'name': 'Parahouse Tunis',
  if (includeNature) 'nature': nature,
  'city': 'Tunis',
  'permissions': ['manage', 'sell', 'receive'],
  'onboardingStep': 1,
  'version': 1,
};

void main() {
  group('store nature', () {
    test('a store is a pharmacie or a parapharmacie, never both', () {
      expect(
        Store.fromJson(storeJson(nature: 'pharmacie')).nature,
        'pharmacie',
      );
      expect(
        Store.fromJson(storeJson(nature: 'parapharmacie')).nature,
        'parapharmacie',
      );
      // The wire value is a single member of the closed set.
      expect(storeNatures, ['pharmacie', 'parapharmacie']);
      expect(isStoreNature('pharmacie'), isTrue);
      expect(isStoreNature('parapharmacie'), isTrue);
      for (final rejected in [
        'pharmacie et parapharmacie',
        'both',
        'Pharmacie',
        'pharmacie,parapharmacie',
        '',
      ]) {
        expect(isStoreNature(rejected), isFalse, reason: rejected);
      }
    });

    test('a store created before the nature keeps it unknown', () {
      final legacy = Store.fromJson(storeJson(includeNature: false));
      expect(legacy.nature, isNull);
      expect(legacy.hasNature, isFalse);
      expect(storeNatureLabel(legacy.nature), 'Nature non renseignée');
      // The editor asks rather than proposing a value.
      expect(storeNatureSelection(legacy.nature), isEmpty);
      expect(storeNatureSelection(null), isEmpty);
    });

    test('an explicit null and an absent nature behave the same', () {
      expect(Store.fromJson(storeJson(nature: null)).nature, isNull);
      expect(
        Store.fromJson(storeJson(includeNature: false)).toJson()['nature'],
        isNull,
      );
    });

    test('a value this client cannot name never becomes a label', () {
      final unknown = Store.fromJson(storeJson(nature: 'officine'));
      expect(unknown.nature, isNull);
      expect(storeNatureLabel(unknown.nature), 'Nature non renseignée');
      expect(storeNatureSelection(unknown.nature), isEmpty);
    });

    test('a recorded nature survives a payload round trip', () {
      final store = Store.fromJson(storeJson(nature: 'pharmacie'));
      expect(Store.fromJson(store.toJson()).nature, 'pharmacie');
      final legacy = Store.fromJson(storeJson(includeNature: false));
      expect(Store.fromJson(legacy.toJson()).nature, isNull);
      expect(legacy.toJson()['nature'], isNull);
    });

    test('each nature keeps its own help text and a shared fallback', () {
      expect(
        storeNatureHelpText('pharmacie'),
        isNot(storeNatureHelpText('parapharmacie')),
      );
      expect(storeNatureHelpText('parapharmacie'), contains('parapharmacie'));
      expect(storeNatureHelpText(null), contains('pharmacie'));
      expect(storeNatureLabel('parapharmacie'), 'Parapharmacie');
    });
  });
}
