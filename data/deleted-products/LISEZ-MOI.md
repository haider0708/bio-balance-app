# Copie des données retirées du catalogue — 1er octobre 2026

- `produits-supprimes.*` : les 13 produits hors de la liste des 39 codes-barres (10 repulpeurs de lèvres, 2 Acnevit, 1 produit « TEST »), avec leur ancien prix, leur description et leur photo.
  - 12 ont été **supprimés** de la production.
  - **BB-WEB-55 (Repulpeur Rosy Petal N°05)** est seulement **désactivé** : mes essais (commandes, stock, une vente) y sont rattachés ; l’historique ne s’efface pas ligne à ligne.
- `anciens-prix-des-39-produits.csv` : les prix qui étaient enregistrés avant leur retrait. Les prix sont maintenant vides dans les données et dans l’application ; certains étaient des tarifs de démonstration ou de revendeur.
- `../backups/catalog-before-cleanup-2026-10-01.json` : sauvegarde complète de la table produits (52 lignes) avant nettoyage.
- Chaque suppression est aussi dans le journal d’audit du serveur (`catalog.delete`, ligne complète).
