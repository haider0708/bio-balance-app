# BioBalance 1.1.0+4 — candidate de refonte

Navigation administrateur réseau → groupe → magasin, sélecteurs indépendants, tableaux de bord par rôle et période, invitations et guide de création de groupe. Les responsables gèrent tous les magasins de leur groupe ; les vendeurs restent affectés aux magasins autorisés.

L’interface utilise blanc, menthe et émeraude, Inter, Lucide et des photographies produit protégées et mises en cache. Les pages de commandes conservent leur identité pendant les synchronisations. Les brouillons et opérations hors ligne restent attachés au compte et au magasin d’origine.

Le catalogue garde ses 51 références et 39 codes-barres, avec 12 codes absents signalés et sept prix de démonstration séparés des noms. Les prix magasin ne sont pas écrasés. Les exports couvrent la sélection complète, avec préparation bornée par worker. Les retours corrigent le reporting de la période de vente initiale.

Six migrations additives et backfill réconcilié sont déployés sur `https://api.galylio.com`. Images API/média `09217a6`, quatre processus HTTP, workers séparés, Nginx et PostgreSQL. Aucun Firebase. Les historiques et identifiants sont conservés ; aucun stock de démonstration n’est recopié dans un nouveau groupe.

La candidate Android porte le code de version 4 et conserve la clé d’application privée ; l’AAB conserve la clé d’upload. Les signatures et l’alignement natif 16 Kio sont vérifiés. Les empreintes et la révision exacte figurent dans le manifeste du dossier de build. Installation avec `adb install -r` uniquement sur l’appareil autorisé ; ne pas désinstaller ni effacer les données pour contourner une erreur de signature.

Preuves : [registre de refonte](redesign-2026-09-23.md), [captures](screenshot-inventory-2026-09-23.md), [conditions de diffusion](release-gates.md). Les quatre jobs CI sont réussis sur `09217a6` : backend, Android, parcours/reprise Android et compilation iOS non signée.

La qualification de pic de charge de la refonte reste ouverte : sur l’hôte de développement, lectures/écritures p95 323/708 ms à 200 req/s dépassent les cibles 300/700 ms. L’installation Samsung attend sa connexion ADB ; performances physiques Android 4 Go, iOS, lecteurs d’écran et recette pilote restent à valider. Cette candidate n’est pas une attestation de préparation au déploiement sur 500 magasins.

Publication Play/App Store, signature Apple, pilote commercial, sauvegardes hors VPS et haute disponibilité restent hors de cette refonte. Les sauvegardes locales ne couvrent pas la destruction du VPS.
