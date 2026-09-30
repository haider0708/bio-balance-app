/// A store is either a pharmacie or a parapharmacie. The two are mutually
/// exclusive: the wire value is a single member of [storeNatures], never a
/// combination and never a free string.
library;

import 'models.dart' show Json;

/// Wire values, in the order the choice is presented.
const storeNatures = ['pharmacie', 'parapharmacie'];

const storeNatureLabels = {
  'pharmacie': 'Pharmacie',
  'parapharmacie': 'Parapharmacie',
};

const storeNatureHelp = {
  'pharmacie':
      'Officine autorisée à dispenser des médicaments et à les détenir.',
  'parapharmacie': 'Point de vente de produits de parapharmacie, sans dispensation de médicaments.',
};

String storeNatureLabel(String? nature) =>
    storeNatureLabels[nature] ?? 'Nature non renseignée';

String storeNatureHelpText(String? nature) =>
    storeNatureHelp[nature] ??
    'Indiquez si ce magasin est une pharmacie ou une parapharmacie. '
        'La nature est unique et modifiable par votre responsable.';

bool isStoreNature(String? value) => storeNatures.contains(value);

/// Reads the nature from a cached, listed or snapshotted store payload. An
/// absent or unrecognised value stays unknown rather than becoming a guess, and
/// a value this client cannot name never reaches a label or a submitted form.
String? storeNatureOf(Json store) {
  final value = store['nature'];
  return value is String && isStoreNature(value) ? value : null;
}

/// The editor's starting choice. Empty for a store with no recorded nature, so
/// the field asks instead of silently keeping an unrelated selection.
String storeNatureSelection(String? nature) =>
    isStoreNature(nature) ? nature! : '';
