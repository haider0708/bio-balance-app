# Scanner et ressources mobiles — 22 septembre 2026

Implémentation : **`873f641`**, branche `codex/biobalance-app`. Flutter 3.47.5 / Dart 3.13.4, dépendances verrouillées inchangées. Les optimisations conservent les règles métier, les données locales, les brouillons et les opérations en attente.

## Scanner

Le mode précédent `noDuplicates` analysait chaque image de la caméra. Le scanner utilise désormais le mode `normal` avec un intervalle de décodage de 250 ms ; cet intervalle ne limite pas la fréquence de la prévisualisation. La résolution demandée sur Android reste 640 × 480, sans copie des images vers Dart, inversion des couleurs ni zoom automatique. Tous les formats pris en charge restent activés. Le modèle Android ML Kit est embarqué par la dépendance verrouillée : son téléchargement n’est pas requis au premier scan, et aucun projet Firebase n’est utilisé.

`ScannerViewModel` possède le contrôleur et sérialise les transitions natives. Une autorisation accordée après fermeture ne laisse pas la caméra active. La caméra s’arrête après une capture, en arrière-plan ou lorsque sa route n’est plus courante. Une fermeture/disposition attend les transitions déjà engagées. Les événements répétés ne produisent qu’un résultat par session. Les valeurs vides sont ignorées ; une erreur de décodage conserve une recherche manuelle et une reprise explicite.

Le cadre fixe indique la zone reconnue ; il sert à guider la sélection, pas à prétendre que l’image est recadrée avant analyse native. Retour haptique unique, état réel de la torche, contrôles disponibles selon la caméra, orientation libre et recherche manuelle conservée. Le contrôle paysage à 200 % de texte a détecté un dépassement corrigé par une disposition adaptative.

La recherche exacte par code et par identifiant utilise des index en mémoire. L’équivalence UPC-A / EAN-13 à zéro initial est un secours validé par chiffre de contrôle ; elle ne modifie ni les identifiants enregistrés ni les zéros significatifs. Les produits archivés ne sont pas proposés comme ventes scannées.

## Interface et travail en arrière-plan

- Stock et catalogue : création des cartes à la demande pendant le défilement. Le test à 2 000 produits conserve moins de 20 cartes initialement et moins de 25 après déplacement.
- Stock : résumés réutilisés pendant la saisie et les changements de statut de synchronisation. Ils sont invalidés lorsque les données ou le jour tunisien changent. Au-delà de 400 produits ou 1 200 lots, préparation dans un isolate, avec indicateur de chargement, un seul calcul actif et abandon des résultats d’un ancien magasin. Les erreurs restent récupérables.
- Recherche : texte normalisé préparé une fois par objet produit, requête normalisée une fois ; aucun appel réseau requis pour rechercher les produits en cache.
- Images protégées : hauteur de décodage adaptée à la taille affichée et à la densité de l’écran, plafonnée à 1 024 pixels. Les contrôles d’origine et d’autorisation restent en place.
- Synchronisation périodique : arrêt des nouveaux cycles en arrière-plan ou après destruction du workspace, reprise au retour. Une transaction déjà engagée termine normalement et les opérations restent durables.
- Notifications : un seul appel à la fois, toutes les quatre secondes après une réponse réussie pendant que la boîte est visible. Suspension hors de la route/au second plan ; délai progressif 8/16/32/60 secondes après échec et arrêt sur perte d’accès confirmée. Les résultats identiques ne reconstruisent pas la liste.

## Vérifications et mesures

**96 tests Flutter réussis**, analyse statique sans constat. Quatre tests historiques dépendant d’un serveur restent exclus de cette exécution et ne sont pas comptés comme réussis. La suite inclut les reprises SQLite, ventes, formulaires, sécurité, sessions, vidéos et dispositions, ainsi que 13 nouveaux tests de scanner et ressources.

Le scanner est testé avec un adaptateur natif contrôlé : fermeture pendant l’autorisation, reprise pendant un arrêt lent, événements vides/répétés, erreur puis reprise et 30 cycles d’ouverture/capture/fermeture sans session active restante. Les tests vérifient aussi la suspension du polling, l’absence de requêtes superposées, les droits expirés, les changements rapides de magasin pendant l’indexation et la construction paresseuse des listes.

Mesures Linux sur le même poste que les [mesures précédentes](performance-evidence.md), sans build Android simultané. Ce sont des mesures de calcul/SQLite sous Flutter test VM, pas des mesures sur téléphone.

| Calcul sur 2 000 produits / 6 000 lots, 120 requêtes | p95 |
|---|---:|
| Ancien filtrage et recalcul des résumés de toutes les cartes | 16,413 ms |
| Filtrage des résumés préparés | 0,531 ms |

La préparation initiale complète prend 66,327 ms de temps écoulé, transfert et création de l’isolate inclus ; le calcul est effectué hors du thread UI. Ces résultats ne mesurent pas le rendu graphique.

La non-régression du benchmark SQLite historique donne : sauvegarde locale durable p95 **11,499 ms** (120 ventes), chargement/changement de magasin **8,333 ms** (100 mesures), réouverture et chargement **12,131 ms** (30 mesures). Le même protocole avant modification donnait respectivement 10,951 / 7,719 / 10,531 ms : résultats locaux comparables, sans allégation de gain sur la persistance. Son ancienne boucle de recherche est conservée pour cette comparaison ; le nouveau calcul de stock est mesuré séparément.

APK et AAB Android release obfusqués compilés. Vérifications des bibliothèques natives, alignement 16 Kio, absence de DWARF embarqué et politique manifeste réussies. Ces artefacts sont **non signés**, ciblent `api.example.invalid` et servent à vérifier la compilation ; ils ne sont pas des versions de distribution.

Preuves : [résumé JSON et empreintes](../tests/performance/evidence/mobile-resources-2026-09-22.json). Journaux locaux : `.artifacts/evidence/mobile-performance/`. Builds : `.artifacts/releases/builds/20260922T105428Z-android-compile-only/`.

## Vérification physique restante

La fluidité à 60 Hz, le démarrage ≤ 2,5 s, la caméra, la consommation, l’échauffement et la stabilité mémoire doivent être mesurés sur Android physique 4 Go et sur iOS. Aucun benchmark hôte, adaptateur simulé ou succès de compilation ne valide ces objectifs. Un appareil Android 2 Go peut compléter la couverture des téléphones plus faibles.

Suivre le [protocole appareils](../tests/performance/devices.md), notamment les codes imprimés réels, petites étiquettes, faible éclairage, EAN/UPC/Code 128, premiers scans hors ligne, rotation, autorisations et cycles répétés. Conserver modèles d’appareils, traces et distributions de temps ; ajuster résolution/intervalle uniquement à partir de ces mesures.
