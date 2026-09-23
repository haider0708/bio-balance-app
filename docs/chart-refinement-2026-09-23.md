# BioBalance 1.1.3+7 — exploration du graphique

## Changement

Le graphique devient un module d’exploration compact : tracé émeraude, dégradé discret, points visibles, halo sur le jour choisi, réticule et bulle ancrée au point. Le montant du jour apparaît au-dessus du tracé, sans grande carte séparée. Les axes restent lisibles et les montants conservent les millimes exacts, avec séparateurs de milliers.

- Trois mesures issues des mêmes données chargées : montant net, unités nettes et ventes enregistrées. Changer de mesure conserve le jour sélectionné.
- Ligne de moyenne quotidienne, calculée sur tous les jours de la période, jours sans ventes compris. Le signe ≈ indique un arrondi d’affichage. « Meilleur jour » sélectionne le maximum de la mesure choisie ; à égalité, le premier jour est retenu.
- Toucher/glisser, précédent/suivant, historique du jour et liste détaillée restent disponibles. L’exploration ne déclenche pas de nouvelle requête réseau.
- Vue agrandie avec nom du périmètre et dates ; présentation compacte en paysage, sélection conservée au retour. Aucun verrouillage d’orientation.
- À plus de 150 % de texte, le détail exact reste dans le bloc accessible au-dessus du tracé ; la bulle dupliquée est masquée pour ne pas recouvrir les données.
- Transitions brèves des sélecteurs, désactivées quand le système demande moins d’animations. Le tracé ne rejoue pas d’animation pendant la synchronisation ou le glissement.
- Calendrier borné à 366 jours ; nombre de libellés d’axe et de points décoratifs adapté à la largeur. Tous les jours restent sélectionnables et accessibles dans la liste paresseuse.

Les prix, stocks, points de récompense et calculs de reporting ne changent pas. Aucun changement backend, aucune migration, aucune nouvelle dépendance. Les paramètres restaurés en 1.1.2 sont conservés.

## Correction de navigation

Un test reproduisait un historique ouvert sur le magasin Sousse depuis un graphique de Tunis lorsque l’espace sous-jacent avait changé. Les liens de ventes capturent désormais le périmètre du tableau de bord d’origine au lieu de relire la sélection courante. La régression vérifie identifiant du magasin, groupe, titre et jour.

## Vérification

Huit scénarios ajoutés couvrent les mesures et la moyenne avec jours nuls, le détail exact de la bulle, l’agrandissement et son retour, la double ouverture, le changement de magasin sous un graphique ouvert, le rafraîchissement des données, les périodes vides/annuelles à 200 %, les animations réduites et les captures portrait/paysage. Ils complètent les tests de toucher/glisser, dates et paramètres existants.

La revue visuelle a corrigé un symbole de légende absent de la police, réduit la hauteur des commandes en paysage et réservé de la place à la bulle pour qu’elle ne masque pas le point sélectionné. Les captures utilisent des données synthétiques identifiées dans les tests ; elles ne représentent pas une nouvelle saisie commerciale.

Analyse Flutter sans diagnostic ; suite complète : **239 tests réussis**, quatre scénarios à fixtures restent ignorés dans la commande générique. Aucun tap de test manqué. La régression de périmètre a d’abord échoué (Sousse au lieu de Tunis), puis réussi après correction. Journaux locaux : `.artifacts/chart-refinement-analyze.log`, `.artifacts/chart-refinement-full-tests.log` et `.artifacts/chart-refinement-scope-regression-before.log`. Le commit, les signatures et l’installation sont enregistrés après livraison. Les tests physiques de performance Android 4 Go et la qualification iOS restent distincts de cette mise à jour.
