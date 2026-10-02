# Jeu de données de présentation

Après `scripts/reset-business-keep-accounts.sql` (sauvegarde vérifiée, API arrêtées) : `structure.sql` (groupe, magasins, grossiste, comptes rattachés, chaîne de prix) puis `seed.cjs` (stock d’ouverture, 14 jours de ventes, retours, commandes et livraisons avec QR, récompenses, signalements) exécuté dans un conteneur API : `ssh vps 'biobalance-compose exec -T api1 node -' < seed.cjs`. Tout passe par les services applicatifs ; `rehearse.sh` rejoue l’ensemble sur une base de répétition locale.
