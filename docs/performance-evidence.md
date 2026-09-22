# Mesures de performance — étape 10

## Environnement

Mesures locales du 21 septembre 2026 sur Linux, Intel i5-1135G7 (4 cœurs physiques / 8 threads), 16 Go de RAM et SSD NVMe. Node 24.21.0, PostgreSQL 17.7, k6 2.3.0. Deux processus API en mode production, accès direct réparti entre leurs ports locaux. Émulateur et builds arrêtés pendant la mesure.

Ces résultats excluent Nginx/TLS, les workers et les contraintes CPU du Compose. Ils ne qualifient pas le VPS de référence ni les appareils physiques. Le scénario versionné utilise 125 organisations, 500 magasins, 5 000 comptes, 300 000 lots et deux millions de ventes historiques avec journaux associés. Les comptes et sessions sont synthétiques ; leurs secrets restent dans un fichier local privé ignoré par Git.

## Méthode et corrections

`tests/load/api.js` conserve les curseurs par compte/magasin, termine les pages figées avant de les avancer et distingue le curseur d’écriture du curseur de lecture. Le mélange inclut snapshots, historiques paginés, classement, boîte de réception, inventaire et environ 10 % de ventes. Le contrôle final compare stocks/versions aux mouvements, soldes aux points et ventes à leurs révisions.

Les premières mesures ont échoué au pic : saturation CPU des API, latences dépassant une seconde et itérations non exécutées. Un premier essai était en mode développement ; le harnais impose désormais le mode production. Les profils ont conduit à regrouper les vérifications d’identité/droits, supprimer les lectures vides/répétées des snapshots, regrouper leurs petites collections et les lectures d’alertes, et simplifier les projections paginées. Les contrôles restent dans la transaction autorisée. Les soldes JSON intermédiaires sont convertis en chaînes avant transport pour préserver les entiers au-delà de 2^53.

Les conflits de sérialisation signalés directement par l’adaptateur au commit sont désormais repris avec une limite de quatre tentatives. Les autres erreurs ne sont pas assimilées à un conflit récupérable. Tests de contrats, reprise hors ligne, pagination, droits révoqués, montants exacts et alertes repassés après ces modifications.

## Charge API finale

Scénario terminé avec code de sortie zéro : **100 requêtes/s pendant 5 minutes, puis 200/s pendant 30 secondes**. 36 001 requêtes exécutées, 3 603 ventes acceptées, zéro erreur HTTP/métier et zéro itération perdue. Les quatre contrôles d’intégrité passent ; la base conservée contient 2 015 587 ventes après les essais successifs.

| Phase | Lecture p95 | Écriture p95 |
|---|---:|---:|
| 100 requêtes/s | 20,91 ms | 49,28 ms |
| 200 requêtes/s | 164,78 ms | 367,87 ms |
| Seuil | ≤300 ms | ≤700 ms |

[Résumé k6 complet](../tests/performance/evidence/api-load-2026-09-21.json). Journaux/profils et contrôles locaux : `.artifacts/evidence/step10/`. Empreinte SHA-256 du manifeste des sources API mesurées : `7b7c2e5cc8458d4a206e8409060c6e75c21781f3bd24d044396ab1813003ac7b`. Les sources API du commit `dfeeacd` correspondent à ce manifeste. Les échecs précédents sont conservés séparément dans les preuves locales et ne sont pas présentés comme des passes.

## Contrôle après l’audit du 22 septembre

La passe de non-régression du **22 septembre**, après l’audit de sécurité et de logique, a réexécuté le même scénario sur le même hôte : 36 001 requêtes, 3 603 ventes acceptées, zéro erreur ou itération perdue. p95 lecture/écriture : **18,36/36,62 ms** à 100 req/s et **104,87/214,55 ms** à 200 req/s. Les quatre contrôles d’intégrité passent (2 022 794 ventes conservées). Voir le [résumé k6](../tests/performance/evidence/api-load-2026-09-22.json), le [manifeste des sources](../tests/performance/evidence/api-sources-2026-09-22.json) et [l’audit](audit-2026-09-22.md), qui conserve aussi l’échec intermédiaire corrigé. Les exclusions Nginx/workers/VPS de cette mesure restent identiques.

## SQLite et recherche sur l’hôte

Résultats reproductibles : [JSON du benchmark](../tests/performance/evidence/host-sqlite-2026-09-21.json).

| Mesure | Échantillons | p95 |
|---|---:|---:|
| Vente enregistrée avec outbox durable | 120 | 15,580 ms |
| Chargement/changement de magasin en cache | 100 | 11,505 ms |
| Recherche dans 200 produits en cache | 100 | 0,184 ms |
| Réouverture SQLite et chargement | 30 | 15,481 ms |

Quatre magasins en cache, 600 lots et 100 ventes récentes par magasin, 120 opérations en attente. Flutter test VM sur Linux : ces valeurs ne mesurent ni le démarrage natif ni la fluidité graphique.

## Validations externes restantes

Le scénario a depuis été exécuté sur le VPS avec quatre API, Nginx et workers actifs : voir [qualification VPS](vps-readiness-2026-09-22.md). Les objectifs physiques (Android 4 Go, iOS, démarrage ≤2,5 s, sauvegarde ≤250 ms, recherche ≤150 ms et moins de 1 % d’images en retard) restent à démontrer. Procédure : [appareils](../tests/performance/devices.md). Aucun résultat sur émulateur ou hôte n’est compté comme validation physique.

## Renforcement de sécurité du 22 septembre

Nouvelle charge avec les budgets compte actifs : 36 001 requêtes, zéro erreur ou itération perdue ; p95 lecture/écriture 26,11/46,69 ms à 100 req/s puis 124,47/232,06 ms à 200 req/s. 3 602 nouvelles ventes, aucune divergence des projections. Voir `tests/security/evidence.json`. Deux processus API locaux, mêmes limites d’interprétation que la mesure précédente : VPS, Nginx/workers et appareils physiques non qualifiés par ce test.

## Scanner et interface mobile du 22 septembre

Le commit `873f641` limite le décodage caméra, construit les grandes listes à la demande et prépare les grands index de stock hors du thread UI. Comparaison du calcul de filtrage sur 2 000 produits / 6 000 lots : p95 16,413 ms auparavant, 0,531 ms avec résumés préparés. Préparation initiale : 66,327 ms écoulées, dans un isolate. Sauvegarde SQLite durable : 11,499 ms p95 sur l’hôte. Ces mesures n’établissent pas les temps caméra, le budget de rendu ou la consommation sur téléphone. [Rapport et limites](mobile-performance-2026-09-22.md), [preuves JSON](../tests/performance/evidence/mobile-resources-2026-09-22.json).
