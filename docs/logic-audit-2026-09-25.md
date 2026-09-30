# Revue logique — 25 septembre 2026

Candidate Android **1.1.10+14**, après 1.1.9+13. Cette passe vérifie les règles opérationnelles, les accès et les courses de synchronisation ; elle ne constitue pas une garantie d’absence de tout défaut futur.

## Défauts reproduits et corrigés

### Rafraîchissement et envoi concurrents

Un rafraîchissement pouvait commencer avant une nouvelle réception locale, puis obtenir un snapshot incluant cette réception déjà acceptée pendant la requête. Son jeu d’acquittements avait été capturé avant la création de l’opération. L’effet provisoire restait donc ajouté à un stock serveur qui le contenait déjà : **réception de 2 unités affichée temporairement comme 4**, avec une version de lot également trop élevée.

`OfflineRepository` sérialise désormais les lectures serveur et les envois par session, compte et magasin. La récupération finale s’exécute dans la même séquence sans s’attendre elle-même. La saisie locale reste indépendante du réseau ; les autres magasins conservent leur séquence indépendante. Les appels de synchronisation simultanés partagent toujours le même résultat.

### Lecture locale incohérente

La lecture du cache et celle de l’outbox utilisaient deux états SQLite potentiellement différents. L’installation d’un snapshot entre ces lectures pouvait faire disparaître momentanément une réception affichée. Elles s’exécutent maintenant dans une transaction de lecture commune ; le décodage et les projections se font après la lecture, hors de la section protégée.

Quatre régressions contrôlent les quantités et versions pendant les réponses retardées, le déblocage après échec réseau, et le refus d’une session remplacée avec reprise sous le compte d’origine. Les deux premiers défauts ont été reproduits avant correction ; journaux `.artifacts/logic-audit-race-before.log` et `logic-audit-race-after.log`.

## Règles examinées

| Domaine | Vérification |
|---|---|
| Commandes | Annulation responsable avant préparation ; préparation/annulation concurrentes ; modification sans réduire les unités engagées ; historique conservé |
| Livraisons | Expédition sans stock ; réception physique unique ; réception partielle, colis absent, remplacement, dommages, refus et surplus |
| Ventes et retours | Calcul exact TND ; lots/péremptions ; correction compatible avec les retours ; attribution originale ; points et stock transactionnels |
| Récompenses | Réservation, annulation, remise, stock produit, soldes négatifs et classement distinct des dépenses |
| Accès | Périmètre groupe/magasin, vendeur limité à son magasin, propre accès du responsable protégé, dernier responsable, invitation unique et codes expirés/consommés |
| Synchronisation | Identifiants/payloads stables, réponses perdues, dépendances, conflits, changement de compte, migrations locales et reprise après interruption |
| Interface | Suite de formulaires, permissions par rôle, états de synchronisation, dispositions étroites/paysage et textes agrandis existante relancée |

Les surplus physiques restent stockés et signalés comme écarts ; ils ne deviennent pas silencieusement des quantités approuvées de commande. Les lots épuisés restent disponibles dans l’historique et les corrections qui les référencent, sans être proposés pour une nouvelle vente. Aucune règle métier approuvée n’est modifiée par cette passe.

## Résultats locaux

- **133 tests backend réussis**, 13 suites avec PostgreSQL isolé, dont sécurité, identité, stock, commandes, invitations, notifications, médias et email.
- **291 tests Flutter réussis** ; les quatre scénarios dépendant d’un laboratoire sont distingués par la commande générique. Analyse Flutter sans diagnostic.
- **Deux parcours HTTP/SQLite/PostgreSQL réussis** : 5 opérations uniques, 6 mouvements, 3 révisions, stock vendable 7/endommagé 1/version 7, 20 points. Le lot manquant en vente produit une sortie réelle sans réception artificielle.
- **38 tests de livraison logicielle, 6 tests opérationnels et 14 tests catalogue réussis**, ainsi que le scénario de reprise des opérations du harnais de charge. Ce dernier ne constitue pas une nouvelle mesure de capacité.
- VPS : quatre API, workers normal/média, PostgreSQL et Nginx sains ; HTTPS `/health` répond `200`. Aucun service ni donnée de production modifié.

Journaux sous `.artifacts/logic-audit-*`. Les résultats de contrats, CI, signatures et installation sont consignés ci-dessous après exécution.

## Compatibilité et vérification manuelle

Aucun changement backend, API, PostgreSQL ou schéma SQLite. Les comptes, brouillons, identifiants, payloads, dépendances, dates de reprise et historiques sont conservés. Le backend compatible `3f180ba` reste en service. L’installation se fait avec mise à jour de la signature existante, sans effacement.

À tester sur le Samsung : recevoir puis vendre pendant un rafraîchissement, couper/rétablir le réseau, changer de magasin avec une saisie en attente, vérifier les mêmes quantités après synchronisation, puis parcourir commande → préparation → expédition → réception avec les comptes responsable/admin. Un vendeur ne doit pas recevoir ni administrer les stocks.

**Téléphone non connecté lors du contrôle ADB** : installation et essai tactile de cette candidate restent en attente. Les tests automatisés n’attestent pas une qualification physique iOS, les objectifs de performance sur appareil de référence, ni la recette pilote. Les limites de capacité déjà documentées et les fonctionnalités différées restent distinctes de cet audit.
