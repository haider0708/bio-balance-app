# BioBalance 0.1.0+1 — candidat de validation

Application française Flutter pour administrateur, responsable et vendeur : organisations/magasins/équipes, catalogue, lots/péremptions, ventes/corrections/retours, commandes/livraisons, points et récompenses par magasin, formation et notifications. TND exact au millime, attribution et historique conservés.

La synchronisation conserve les commandes et brouillons par compte/magasin, reprend les transmissions incertaines, applique les dépendances et protège les changements de droits. Un vendeur peut déclarer le lot manquant d’une vente sans inventer de réception. Les points sont calculés à la première synchronisation acceptée.

Les douze étapes ont un registre dans `docs/implementation-status.md`. Les contrôles locaux incluent PostgreSQL/RLS, contrats HTTP/Dart, reprise SQLite, parcours Android natifs, vidéo hors ligne, charge synthétique, Compose/TLS local, sauvegarde avec médias et rollback compatible. Consulter les preuves : les essais locaux ne valent pas une qualification sur le VPS ou sur des téléphones physiques.

**Diffusion non autorisée par les preuves actuelles.** Les APK/AAB `compile-only` sont non signés, utilisent `https://api.example.invalid` et ne sont pas connectables à une installation. Le debug est signé uniquement avec la clé de développement Android. Aucun compte réel ni credential serveur n’est inclus.

À fournir/vérifier : domaine et VPS, SMTP réel, certificats/signatures, dépôt/CI macOS, appareils physiques et cinq magasins pilotes pendant au moins deux semaines. Les versions signées devront être reconstruites avec leur configuration plateforme puis soumises à la recette.

Sont reportés : abonnements payants, administration web, WhatsApp, classements régionaux/nationaux, sauvegarde hors serveur et haute disponibilité. Les sauvegardes locales ne couvrent pas la destruction du VPS.

## Audit final du 22 septembre

Contrôle de l’émetteur à l’activation d’invitation, récupération interdite aux comptes désactivés, sessions iOS liées à l’appareil, nettoyage des snapshots expirés et codes d’emails en échec. Soumission locale distincte de son affichage, éditions/brouillons sérialisés, dommages et retours liés au lot/à la vente et terminés atomiquement avec leur outbox, initialisation récupérable et régressions UI. Voir [preuves et limites de qualification](final-audit-2026-09-22.md).

Appliquer la migration additive `202609220004_snapshot_cleanup`. Les anciennes installations iOS doivent se reconnecter après la migration du service Keychain ; les opérations locales restent conservées pour le compte d’origine. Les anciens brouillons d’ajustement sans identifiant de lot sont conservés mais ne sont pas réutilisés automatiquement sur un autre lot. Aucun Firebase n’est requis ; notifications dans la boîte VPS et alertes OS app fermée reportées.
