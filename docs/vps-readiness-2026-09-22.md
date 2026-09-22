# BioBalance : catalogue et exploitation du VPS

Ce relevé complète les preuves historiques de déploiement. Il concerne BioBalance sur le VPS partagé `go2code` et l’API `https://api.galylio.com`. Il ne valide ni les autres applications du serveur, ni la recette sur téléphones physiques.

## Données utilisables pour la démonstration

- 51 produits actifs, 51 photos traitées et 39 codes EAN issus du classeur fourni.
- 42 prix relevés sur le site BioBalance tunisien, deux chez MaPara Tunisie et sept tarifs explicitement fictifs autorisés par le propriétaire. Les deux déodorants restent séparés ; aucun des 12 codes absents n’est inventé.
- Cinq magasins marqués `DÉMO —`, deux organisations, sept comptes fictifs, 255 configurations produit/magasin et 267 lots.
- 100 ventes, 110 révisions, 392 mouvements, 115 écritures de points, 10 récompenses et 10 demandes, avec exemples de remise, attente, retour et écart de stock. Cinq commandes et quatre livraisons couvrent réception complète, partielle et manquante.
- Un guide publié et cinq fiches de formation en brouillon pour validation métier.

L’import et les réceptions utilisent les API et transactions métier. Les reprises conservent leurs identifiants. Les comptes fictifs n’ont déclenché aucun email à un commerce réel. Les sources, tarifs et règles de passage aux données réelles sont dans [le registre du catalogue](catalogue-simulation.md).

## Sauvegarde, HTTPS et supervision

La restauration après import, puis celle du backup final `20260922T214318Z-fb17bd65` après déploiement, comparent 17 tables métier et vérifient les tailles/SHA-256 des 53 médias prêts, dont les photos, une image PNG et une vidéo H.264. La base et les fichiers de restauration isolés sont retirés après réussite. Les empreintes agrégées des lignes SQL sont des MD5 de comparaison, distinctes des SHA-256 des fichiers.

Les sauvegardes ont un plafond total de 4 Gio, une réserve disque de 10 Gio et une rotation de 7 quotidiennes/4 hebdomadaires. La dernière copie valide est protégée ; les temporaires échoués sont nettoyés. Les journaux Docker restent bornés. Après nettoyage du laboratoire et des seules anciennes images BioBalance, le VPS dispose de 29,26 Go libres (27,25 Gio), avec 82,4 % occupés ; les backups totalisent environ 4,49 Mio. Les images courante et précédente sont conservées. Ce mécanisme ne protège pas contre la perte du VPS lui-même.

Le renouvellement ACME limité à `api.galylio.com` et le hook de rechargement Apache ont réussi. `biobalance-tls.timer` contrôle ce certificat indépendamment des anciens certificats des autres sites.

La supervision GitHub externe contrôle HTTPS et un rapport SSH sans accès shell. Elle notifie les changements d’incident, espace les rappels de six heures et exige deux contrôles sains avant le rétablissement. Le cron est configuré toutes les dix minutes environ, sans garantie de ponctualité GitHub. Une exécution planifiée réelle (`35776577391`) a détecté le seuil disque atteint pendant le laboratoire et transmis l’alerte au relais SMTP. Après suppression du laboratoire, les contrôles externes `35788371179` et `35788470485` sont sains ; le second transmet l’email de rétablissement au relais SMTP. Aucune réception en boîte principale n’est déduite de cette acceptation. Les preuves des tests du runner et des messages SMTP sont dans le registre d’implémentation.

## Capacité

La qualification utilise un projet Compose jetable sur loopback, avec TLS vérifié, Nginx, quatre API, les deux workers et PostgreSQL. Configuration retenue pour la mesure finale : quatre API de 768 Mio/1,5 CPU chacune, worker 384 Mio/0,5 CPU, média 1 Gio/1 CPU, PostgreSQL 2 Gio/4 CPU, Nginx 128 Mio/1 CPU. PostgreSQL utilise 256 Mio de buffers partagés, 4 Mio par opération de tri, 60 connexions, 1 024 verrous de prédicat par transaction et 512 par relation ; le seuil souple de WAL est de 512 Mio. Le générateur k6 tourne sur le poste opérateur, relié par un tunnel SSH au port TLS loopback du laboratoire. Les temps client incluent ce trajet ; le temps serveur Nginx est relevé séparément. Aucun port de test public n’est ouvert.

Les données comprennent 500 magasins, 5 000 comptes métier, un administrateur technique sans connexion, 200 produits, 300 000 lots et au moins deux millions de ventes avec leurs historiques. Les comptes et certificats de ce laboratoire ne sont jamais ceux de production. Le mélange cible 90 % de lectures et 10 % de ventes, à 100 requêtes/s pendant cinq minutes puis 200/s pendant trente secondes. Le même pool de clients, les connexions et les curseurs par compte/magasin sont conservés pendant le passage au pic. Les réponses de synchronisation explicitement temporaires sont reprises au plus deux fois avec le même identifiant et le même JSON ; leur attente compte dans la latence métier et les tentatives supplémentaires restent visibles dans les métriques HTTP. Les erreurs terminales et reprises épuisées font échouer le test.

Le premier essai échoue aux seuils de latence. Les plans SQL montrent une lecture excessive de l’historique des ventes et des points mensuels. Le correctif `6a43944` conserve RLS et les historiques, optimise l’évaluation du contexte de lecture et utilise des bornes de mois indexables. La passe longue révèle ensuite la rétention excessive de verrous de prédicat. `2c89538` réserve la sérialisation aux commandes métier et utilise des instantanés cohérents `RepeatableRead` pour les écrans/pages, avec les mêmes vérifications de session, appartenance et RLS. 26 tests d’intégration, 10 de domaine/reprise, 14 d’audit, 13 de sécurité, 45 contrats HTTP/décodage Dart et les deux parcours de synchronisation réels passent. La répétition finale réussit sur 2 041 301 ventes, avec 35 999 requêtes et 3 614 nouvelles ventes acceptées. Aucun rejet HTTP/métier, aucune reprise nécessaire, aucune itération perdue et aucun écart de stock, version, points ou attribution. Les plafonds CPU sont identiques pour les quatre API après observation du throttling des processus limités à un CPU.

| Mesure p95 | 100 req/s, 5 minutes | Pic 200 req/s, 30 secondes | Cible |
|---|---:|---:|---:|
| Lecture, client externe | 122,36 ms | 277,35 ms | ≤300 ms |
| Écriture HTTP, client externe | 200,47 ms | 549,46 ms | ≤700 ms |
| Vente complète, attentes comprises | 203,90 ms | 550,00 ms | ≤700 ms |
| Lecture, Nginx serveur | 58,00 ms | 223,60 ms | ≤300 ms |
| Écriture, Nginx serveur | 136,00 ms | 490,00 ms | ≤700 ms |

Les tentatives antérieures avec deux pools de clients ne satisfont pas tous les seuils ; elles restent des résultats de stress de reconnexion échoués. La passe réussie utilise un seul pool persistant avec un saut immédiat de débit. Elle ne garantit pas une latence identique lors d’une reconnexion simultanée de tout le réseau ou sous une charge différente des autres applications du VPS. Le test ne mesure pas les performances des téléphones.

Le retour à l’image précédente `2b3769b` est vérifié sur la base migrée (14 migrations) : démarrage, lecture, refus hors magasin et hors organisation, nouvelle vente et rejeu idempotent. Les contrôles de ledger repassent après cette vente. Le laboratoire est supprimé, volumes compris ; ses 331 éléments de preuve restent archivés localement sans secrets de connexion.

## Version déployée et contrôles

Les huit services BioBalance sont sains : quatre API, PostgreSQL, Nginx et les deux workers. Images applicatives `2c89538`, configuration d’exploitation `3be5389`, 14 migrations appliquées. HTTPS/Cloudflare, MFA admin, refus interorganisations et de faux périmètres magasin, déconnexion, accès média protégé, SHA-256 et plages vidéo sont revérifiés après installation. Les 51 produits et les données des cinq magasins sont conservés. Les quatre jobs de [CI 35784854922](https://github.com/haider0708/bio-balance-app/actions/runs/35784854922) passent, y compris les parcours Android et la compilation iOS non signée.

La [preuve structurée](../tests/deployment/catalog-operations-evidence-2026-09-22.json) rassemble versions, mesures, restauration, supervision et limites. Le code mobile n’a pas changé pendant cette passe ; l’APK signé v1.0.0+2 déjà publié reste compatible.

## Limites et actions du propriétaire

Le propriétaire a exclu la réparation de MySQL des autres sites ainsi que la maintenance/redémarrage globale du serveur. Un fichier de table manquant a été détecté pendant la préparation ; aucune restauration de cette autre application n’est déclarée réussie. Une réparation ou mise à niveau générale exige une intervention distincte. Les quotas BioBalance ne réservent pas physiquement les ressources face aux autres applications ; suivre l’espace disponible avant l’extension du réseau.

SPF, DKIM et DMARC sont confirmés PASS par le destinataire, qui a reçu les messages dans Spam. L’authentification du domaine fonctionne ; le classement Gmail reste à surveiller. Marquer un message légitime « Non-spam » et ajouter l’expéditeur aux contacts peut aider ce destinataire, sans garantir le classement des autres boîtes.

Les deux clés Android ont une archive OpenPGP AES-256 dont les sept fichiers ont été vérifiés après déchiffrement. Le propriétaire doit encore conserver l’archive et son secret de récupération séparément sur un support indépendant. Aucun secret n’est publié dans Git.

Restent les tarifs/codes et contenus métier définitifs, les mesures physiques Android 4 Go/iOS, la signature Apple et TestFlight, l’inscription Play et les mises à jour entre canaux, puis le pilote de cinq magasins pendant au moins quatorze jours. La compilation iOS non signée ne remplace pas ces étapes. Notifications OS application fermée, attestation, pinning, sauvegardes hors serveur et haute disponibilité demeurent reportés conformément au périmètre documenté.
