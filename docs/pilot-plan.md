# Pilote BioBalance — cinq magasins, au moins deux semaines

État : **non démarré**, aucune invitation réelle envoyée. Les participants, appareils, dates et responsables restent à nommer. Remplir cette fiche après les portes préalables de `release-gates.md`.

## Préparation

- Choisir cinq magasins avec au moins un responsable et un vendeur chacun ; couvrir Android et iOS, dont un Android 4 Go. Inclure l’administrateur BioBalance dans la recette.
- Attribuer un référent support et une plage de disponibilité ; noter les versions signées, le domaine, les appareils/OS et le début/fin (14 jours minimum).
- Valider stock initial, lots/péremptions, prix TND, points par produit, récompenses et droits avant les ventes réelles. Expliquer le statut local/en attente/synchronisé/à vérifier.
- Tester sauvegarde/restauration, alerte d’exploitation et procédure de retour applicatif avec schéma compatible. Ne jamais rétrograder une base SQLite ou supprimer une outbox pour réparer une synchronisation.

## Recette par rôle

| Rôle | Scénarios requis | Résultat attendu |
|---|---|---|
| Admin | Invitation, MFA, catalogue, formation, préparation/expédition, contrôle global | Accès approprié, médias publiables seulement après traitement, stock inchangé à l’expédition |
| Responsable | Création/reprise du guide, équipe, plusieurs magasins, seuil, commande partielle/manquante, récompense produit | Brouillons liés au magasin, un seul effet de réception, réservation puis débit à la remise |
| Vendeur | Scan/recherche, lot existant/manquant, vente, correction, retour, rupture, mode avion, formation téléchargée | Vente réelle conservée, historique attribué, aucun stock entrant inventé, points au taux accepté lors de la synchronisation |
| Tous | Session expirée, accès retiré, redémarrage, changement de compte, notification et permission refusée | Aucune perte de travail, aucune attribution au mauvais compte, droits revérifiés |

## Suivi des quatorze jours

Jours 1–2 : accompagnement à l’installation, activation et stock initial. Jours 3–7 : usages quotidiens, un cycle hors connexion contrôlé, livraisons partielles et retours. Jours 8–13 : corrections des incidents et répétition des scénarios affectés, vérification des stocks/points avec les responsables. Jour 14 ou plus tard : revue des preuves, incidents et mesures ; décision explicite de clôture ou prolongation. Une interruption significative prolonge la période utile de test.

Chaque jour : examiner opérations en échec/bloquées et ancienneté de synchronisation, crashs, latences, jobs, sauvegardes/disque ; comparer les écarts stock/points signalés avec l’historique. Les ajustements passent par les fonctions auditées, jamais par la suppression d’événements. La fréquence d’inspection doit être organisée avec le responsable d’exploitation ; aucun suivi automatique distant n’est activé par ce document.

## Incidents et élargissement

Utiliser `tests/release/pilot-issues.csv`. Critique : accès non autorisé, perte/duplication d’écriture, attribution erronée, parcours essentiel bloqué sans récupération. Suspendre l’action affectée, conserver les opérations/données et collecter une preuve expurgée. Corriger, rejouer le scénario et les tests dépendants avant reprise. Ne pas demander de mots de passe, secrets MFA ou tokens dans les tickets.

Passer à 50 magasins seulement après ≥14 jours utiles, trois rôles/deux plateformes validés, aucun défaut critique ouvert, restauration opérationnelle et objectifs de performance vérifiés. Définir une période d’observation à 50 avant d’étendre vers 500 ; recontrôler capacité VPS, incidents, synchronisation et support à chaque élargissement. Aucune réussite du pilote ni absence d’incidents n’est présumée ici.
