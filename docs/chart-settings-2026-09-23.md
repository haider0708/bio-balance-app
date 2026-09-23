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

Journaux locaux : `.artifacts/chart-settings-analyze-final.log`, `.artifacts/chart-settings-tests-final.log`, `.artifacts/chart-settings-journeys.log`, `.artifacts/chart-settings-restart.log`. Les captures sont répertoriées dans [l’inventaire](screenshot-inventory-2026-09-23.md). Aucun test backend existant n’est revendiqué comme réexécuté pour cette modification exclusivement mobile. La qualification complète des performances physiques et iOS reste distincte de ces résultats.

La compilation signée, l’installation Samsung et le statut de la nouvelle CI sont enregistrés après livraison.

L’exécution CI précédente `35875356803` a terminé ses parcours de rôles avec succès, puis échoué avant le test de redémarrage : ce harnais cherchait encore l’ancien libellé du lot. Il utilise désormais la clé stable `sale.lot.OPENING`. Cet échec n’est pas présenté comme un test de reprise réussi.
