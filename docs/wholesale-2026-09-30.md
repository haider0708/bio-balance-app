# Grossistes — 30 septembre 2026

Candidate Android **1.2.0+16**, après 1.1.11+15. Non déployée : le backend, la migration et les APK restent à produire et à installer.

## Règles

Voir la [spécification](specification-fonctionnelle.md) et l’[architecture](architecture-technique.md). En bref :

- BioBalance crée le grossiste (nom, adresse, email du compte) ; l’invitation crée son compte responsable et son dépôt. Un compte, un dépôt, aucune équipe, aucune vente.
- Stock initial par lot : BioBalance et le grossiste.
- Grossiste → BioBalance : BioBalance prépare et expédie sans suivre son stock ; le grossiste reçoit par lot avec écarts.
- Magasin : le responsable commande, BioBalance traite ou attribue à un grossiste jusqu’au début de la livraison. Un seul acteur par commande.
- Expédition du grossiste : lots choisis (proposition par péremption la plus proche), stock du dépôt en moins à l’expédition ; stock du magasin en plus à sa réception. Retour : lots remis au dépôt ; perte : non.
- Points du grossiste : par unité livrée et confirmée par le magasin, barème et récompenses définis par BioBalance, séparés des équipes, sans classement.

## Écrans

BioBalance : **Plus → Grossistes** (créer, stock du dépôt, invitation), **Attribuer à un grossiste** dans le détail d’une commande. Grossiste : accueil du dépôt (alertes, commandes à livrer, points), stock, **À livrer** / **Mes commandes**, expédition par lot, points et récompenses. Le responsable voit le grossiste de sa commande et les lots annoncés à la réception.

## Validation locale

- **Backend :** 73 tests d’intégration dont 12 scénarios grossiste sur PostgreSQL réel : création idempotente, invitation et activation, stock initial, commande à BioBalance, attribution/reprise, isolement entre grossistes et avec le responsable, expédition par lot, refus de stock insuffisant ou d’allocation incohérente, flux de synchronisation du dépôt, retour/perte, points à la réception, récompenses, dépôt suspendu. Audit 14, sécurité 10, notifications 5, email 19, domaine 19, médias 5.
- **70 contrats HTTP** vérifiés sur l’API réelle puis décodés par le client Dart régénéré ; dérive du contrat nulle.
- **Flutter :** 302 tests, analyse sans diagnostic, dont le calcul d’attribution, l’expédition par lot et l’exclusion des lots périmés ou excédés.
- Deux parcours HTTP/SQLite/PostgreSQL inchangés (5 opérations, 6 mouvements, 3 révisions, stock 7/1, 20 points).
- Les tests médias et de contrat utilisent ffmpeg : exécutés ici via l’image `biobalance-media` faute d’installation locale.

## Limites connues

- Aucune installation sur téléphone ; interface grossiste et attribution non essayées sur appareil. Aucune qualification iOS.
- L’expédition et le règlement du grossiste exigent une connexion (comme les opérations en ligne existantes) ; le stock initial et la commande à BioBalance restent utilisables hors connexion.
- Pas de prix ni de facturation entre grossiste et magasin ; pas de classement des grossistes ; changement du compte responsable d’un grossiste non prévu (renvoyer l’invitation avant activation uniquement).
- Les fiches du grossiste (nom, adresse) ne se modifient pas encore depuis l’application.
