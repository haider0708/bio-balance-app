# BioBalance 1.1.2+6 — graphique interactif et accès aux paramètres

## Demande et décision de navigation

Le retour utilisateur porte sur le graphique non interactif et les réglages devenus difficiles à retrouver. La refonte avait conservé les réglages dans le « Plus » du magasin, mais réduit le menu supérieur au compte et à quelques actions globales. Ce déplacement était une décision d’implémentation, pas une suppression de fonctions demandée par l’utilisateur.

Le bouton supérieur « Paramètres et gestion » et l’onglet « Plus » utilisent désormais le même écran. Les réglages gardent leur périmètre : activité/configuration/suivi du magasin, gestion du groupe, administration BioBalance, compte et aide. Sans magasin sélectionné, une liste permet d’en choisir un avant de configurer ses prix, points, seuils, coordonnées ou accès. Les vendeurs ne reçoivent aucun nouveau droit. Modifier les informations du groupe conserve le magasin ouvert.

## Graphique

- Axe des dates et échelle TND, grille discrète, points visibles et repère vertical du jour sélectionné.
- Toucher ou glisser pour choisir un jour ; flèches précédent/suivant accessibles aux lecteurs d’écran.
- Date, montant exact à trois décimales, unités nettes et nombre de ventes ; ouverture de l’historique limité à ce jour, dans le même périmètre.
- Liste détaillée chargée paresseusement, y compris les jours sans ventes ; jusqu’à 366 jours.
- Calcul des jours en UTC civil pour éviter les décalages du fuseau du téléphone ; montants conservés en millimes jusqu’au dessin.
- Animations de données désactivées pendant le rafraîchissement. L’exploration ne déclenche pas de requêtes réseau.

## Vérifications et compatibilité

Pas de modification d’API, de migration ou de données métier. Le backend `a9fd576` reste compatible. L’APK suivant conserve l’identifiant et la signature installés, avec version 1.1.2 et code 6.

Onze régressions ajoutées : calendrier/millimes, interaction tactile et ouverture d’un jour, quatre tailles/échelles de texte, période nulle/annuelle, découverte des paramètres depuis le réseau, accès aux réglages à 200 % dans les contextes réseau et magasin, absence de contrôles de gestion pour un vendeur.

Résultats locaux sur le code de cette mise à jour :

| Vérification | Résultat |
|---|---|
| Format et analyse Flutter | Réussis, aucun diagnostic |
| Suite Flutter complète | 231 tests réussis ; 4 tests nécessitant leurs fixtures restent ignorés dans la commande générique |
| Parcours des trois rôles sur Android | 2 tests réussis sur émulateur, API HTTP et PostgreSQL isolés, effets métier vérifiés |
| Reprise Android après arrêt forcé | Identité, identifiant et contenu de l’outbox conservés ; une vente acceptée, stock 7 v3, 30 points |
| Caméra refusée et média hors ligne | Saisie manuelle disponible ; vidéo H.264 vérifiée puis lue hors ligne |
| Revue visuelle | Graphique et paramètres réseau/magasin revus ; portraits, paysage et texte à 200 % couverts par les régressions |

Journaux locaux : `.artifacts/chart-settings-analyze-final.log`, `.artifacts/chart-settings-tests-final.log`, `.artifacts/chart-settings-journeys.log`, `.artifacts/chart-settings-restart.log`. Les captures sont répertoriées dans [l’inventaire](screenshot-inventory-2026-09-23.md). Les suites backend n’ont pas été réexécutées localement pour cette modification exclusivement mobile ; les résultats de la CI sont reportés séparément. La qualification complète des performances physiques et iOS reste distincte de ces résultats.

## Livraison

Code poussé : `95ceaa6f4d31fe629e757c18e2fc511d556f4a55`. APK et AAB signés produits depuis ce commit propre, sans migration ni redéploiement backend. Signature d’application conservée pour l’APK ; signature d’upload distincte vérifiée pour l’AAB. Les contrôles du manifeste, de l’alignement natif 16 Kio et de l’absence de DWARF dans les bibliothèques distribuées ont réussi.

La mise à jour 1.1.1+5 → **1.1.2+6** est installée sur le Samsung SM-G975F avec `install -r`, sans désinstallation ni effacement. UID et date de première installation conservés. L’application a ouvert le tableau de bord réseau synchronisé avec la session administrateur existante. Vérifications sur ce téléphone : sélection du jour par flèche et toucher du graphique, détail exact, ouverture de l’historique au jour choisi, retour Android conservant la sélection, accès au menu « Paramètres et gestion ». Aucun crash ou exception non gérée relevé dans ce processus. Ces essais ne constituent pas une qualification complète des performances physiques.

APK SHA-256 : `edacedc871718af6fea85cac2087b79411257088845b76fbf55a637dd5fd2c4d`.

AAB SHA-256 : `971dafca7ed88aeda41249dc4cdcba7f851e687b4959e1139bc9c8180dddf0ab`.

[Preuves et empreintes](../tests/deployment/chart-settings-evidence-2026-09-23.json). [CI du code livré](https://github.com/haider0708/bio-balance-app/actions/runs/35881790786) : terminée avec succès pour les quatre jobs : backend, Android, parcours Android et compilation iOS non signée.

L’exécution CI précédente `35875356803` a terminé ses parcours de rôles avec succès, puis échoué avant le test de redémarrage : ce harnais cherchait encore l’ancien libellé du lot. Il utilise désormais la clé stable `sale.lot.OPENING`. Cet échec n’est pas présenté comme un test de reprise réussi.
