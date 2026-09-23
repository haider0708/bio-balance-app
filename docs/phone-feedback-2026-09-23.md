# BioBalance 1.1.1+5 — corrections après essai Samsung

Branche `codex/biobalance-app`. Ce changement applique les deux confirmations : rubriques commandes « À préparer », « Expédiées / à réceptionner », « Terminées » ; une invitation active par personne et par groupe.

## Corrections

- Récupération : huit caractères aléatoires majuscules alphanumériques, présentation 4–4 dans l’email et huit cases dans l’app. Collage, remplissage automatique, anciens codes, expiration, remplacement et usage unique conservés. Le succès retourne directement à la connexion. Pas de modification imposée du mot de passe existant.
- Formulaires : un seul défilement vertical de page, champs multilignes qui grandissent, actions accessibles au-dessus du clavier. Application aux écrans de connexion, activation, récupération, édition générique, vente/correction, ligne/lot, commande et formation. Aperçu et enregistrement de formation distincts.
- Navigation : groupe en haut à gauche ; suppression du second sélecteur magasin. Liste des magasins du groupe, tableau de bord réseau, résumé de groupe plus court, détails complets dans le magasin. Les vendeurs affectés à plusieurs magasins conservent une liste des magasins autorisés depuis le groupe.
- Retour Android : transmission au navigateur interne, puis historique des onglets et périmètres ; conservation des brouillons avant changement. Réponses anciennes ignorées après changement de rubrique/périmètre.
- Photos : correction du cache qui retournait sa propre Future depuis `whenComplete`, bloquant sa résolution. Les tests prouvent le chargement réel du fichier, les appels simultanés, l’échec et la reprise ; ils échouent avec l’ancienne implémentation.
- Commandes : trois rubriques avec filtrage serveur avant pagination ; ouverture d’une commande précise, contexte groupe/magasin, lignes, quantités réellement reçues/en route/restantes et historique des réceptions. La réception reste la seule action qui augmente le stock.
- Ventes : magasin et vendeur affichés dans la liste. Lots, péremption, disponibilité et quantités séparés dans l’éditeur de correction.
- Invitations : choix responsable/vendeur, explication des droits, sélection multiple des magasins uniquement pour les vendeurs, renvoi/modification de l’invitation existante. Sérialisation serveur par email/groupe et invalidation de l’ancien code. Un membre existant est géré depuis son accès, sans nouvelle invitation. Un échec de nettoyage local après acceptation ne permet pas une deuxième soumission.

## Compatibilité et livraison

Aucune migration PostgreSQL ou SQLite nécessaire. Identifiants, historiques, files hors connexion et données installées restent conservés. Les réponses de commande ajoutent des champs optionnels ; les anciens clients et anciens codes restent lisibles. Déployer le worker email compatible avant les API. Un retour à une ancienne API doit garder le nouveau worker tant que des emails contenant un code court attendent.

## Vérification

Les journaux de cette itération sont conservés dans `.artifacts/phone-feedback-2026-09-23/`. Résultats locaux :

- Analyse Flutter et compilation TypeScript sans erreur ; format API validé.
- 220 tests Flutter réussis. Quatre tests dépendant de fixtures sont ignorés dans cette commande : le contrat HTTP et les deux parcours de synchronisation sont exécutés séparément et réussissent ; le test de média déployé n’est pas compté comme réussi ici.
- 60 endpoints HTTP vérifiés avec décodage/réencodage Dart ; synchronisation réelle HTTP/SQLite/PostgreSQL réussie, y compris réception → vente → dommage → correction → retour et lot manquant sans réception artificielle.
- Parcours Android natif administrateur/responsable/vendeur réussi sur émulateur API 36 avec API et base isolées. Assertions finales : stock 21, points 20, réserve 0, trois révisions, récompense remise et livraison reçue.
- Régression du cache photo démontrée : les deux tests échouent avec l’ancienne ligne et réussissent avec la correction.
- Captures de 28 écrans, contrôles portrait et paysage à 200 %, révision visuelle des formulaires, commandes et listes avec données.
- Sauvegarde VPS préalable réussie ; restauration isolée et validation de 104 fichiers média traités par taille et SHA-256 réussies.

Les résultats backend définitifs, versions livrées et contrôles après installation sont ajoutés après livraison. Les essais de laboratoire ne remplacent pas la qualification physique des performances ni celle d’iOS.
