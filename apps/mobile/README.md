# BioBalance mobile

Application Flutter Android/iOS en français : vente hors ligne, stock par lot, équipes, récompenses et formation.

- `lib/domain` : modèles et règles ; `lib/data` : API et Drift ; `lib/ui` : vues et view models Provider.
- Outils et commandes : [README du dépôt](../../README.md).
- Configuration, signature et packaging : [livraison mobile](../../docs/mobile-release.md).
- Tests métier et widgets : `flutter test`. Parcours natifs : [harnais isolés](../../tests/journeys/README.md).

`lib/main.dart` est la seule entrée de diffusion. `lib/main_test.dart` reste nécessaire aux tests de performance et ne doit pas être distribué. Les secrets et données de test générées ne sont jamais versionnés.
