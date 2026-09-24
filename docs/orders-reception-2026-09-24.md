# Commandes, réception et équipe — 24 septembre 2026

Candidate 1.1.9+13, après 1.1.8. Conserver comptes, données métier, brouillons et opérations en attente.

## Règles confirmées

- Le responsable commande pour un magasin depuis le groupe ou le magasin. Le magasin est choisi dans l’éditeur et reste attaché au brouillon.
- Il peut annuler une demande avant sa mise en préparation. La vérification est transactionnelle : une préparation concurrente ferme cette possibilité.
- BioBalance prépare puis expédie. Les contrôles administrateur restent audités et respectent les réceptions déjà enregistrées.
- Seule la réception physique augmente le stock. Le responsable saisit quantités réelles, lots et péremptions ; une livraison peut contenir plusieurs lots.
- Une livraison non reçue déclenche un incident et une notification admin, sans entrée de stock. Réception tardive, écarts et remplacement restent traçables.
- Un responsable ne modifie pas son propre rôle ou son propre accès depuis l’équipe. Les autres membres restent gérables.
- Les lots épuisés sont masqués dans les listes opérationnelles et les propositions de vente. Les historiques et allocations originales d’une correction restent accessibles ; les écarts et stocks endommagés ne sont pas effacés.

## Exécution et acceptation

1. Renforcer transitions et annulation responsable, protection de son propre accès, tests PostgreSQL des courses et des permissions.
2. Créer depuis le groupe avec choix de magasin et brouillons isolés. Organiser détail commande, actions suivant le rôle, réception par produit/lot et suivi d’incidents.
3. Filtres stock sur une ligne ; invitations compactes ; équipe sans contrôles sur soi ; sélection de lots et cycle vendeur vérifiés.
4. Tests Flutter, backend, contrats, reprise hors ligne et parcours des rôles. Vérification visuelle téléphone/paysage/grands textes.
5. Déploiement compatible avec sauvegarde vérifiée, APK signés 1.1.9+13, mise à jour des quatre applications sans effacement, preuves consignées ci-dessous.

## Validation locale

- 133 tests backend réussis, dont annulation responsable, concurrence préparation/annulation, préservation du statut après modification, signalement/résolution idempotents, destinataires et blocage de sa propre modification d’accès.
- 287 tests Flutter réussis ; les quatre scénarios dépendant d’un laboratoire restent distincts. Après ajustement visuel final, 75 contrôles ciblés téléphone/paysage 200 % passent. Analyse sans diagnostic ; génération OpenAPI/Dart reproductible.
- 66 contrats HTTP réels validés, puis décodés par le client Dart généré ; deux parcours HTTP/SQLite/PostgreSQL de reprise hors ligne passent (5 opérations, 6 mouvements, 3 révisions, stock 7/1 et version 7, 20 points). Lot manquant : sortie réelle sans entrée artificielle.
- Parcours Android des trois rôles réussi sur émulateur, avec API/PostgreSQL isolés et vérification des stocks, ventes, points et récompenses. Le formulaire de réception est parcouru par produit attendu.
- Captures contrôlées inspectées : [commande responsable](screenshots/orders-responsible-detail.png), [réception](screenshots/refinement-receipt.png), [stock](screenshots/audit-stock.png), [invitations](screenshots/audit-invitations.png). Les scénarios vérifient la conservation du brouillon si le stockage échoue et l’isolation entre magasins.

## Contrats et compatibilité

Aucune migration de base ni réécriture d’historique. Chaque page de commandes synchronisées porte le même résumé de réception et d’incidents ; les signalements restent visibles au-delà de la première page d’alertes. `order.report` et `order.resolve` utilisent les commandes versionnées et idempotentes existantes. L’alerte `order_problem` représente le signalement courant ; le journal append-only conserve chaque motif, auteur et résolution. Le signalement ne modifie ni statut logistique ni stock. Un signalement actif par commande évite les duplications ; un nouveau signalement reste possible après résolution.

Le responsable ne peut annuler qu’avant préparation. L’administrateur conserve les actions auditées, sous réserve des quantités physiquement engagées ou reçues. Le chemin d’expédition direct de l’ancienne API reste compatible pendant la mise à jour des applications ; l’interface guide préparation puis expédition.

La sélection de magasin du nouvel éditeur est temporaire : elle ne remplace pas l’espace derrière la page ni le magasin mémorisé. Les lots vides restent dans les historiques et les brouillons/corrections qui les utilisent ; les quantités négatives et endommagées restent visibles pour régularisation.

## Vérification VPS avant livraison

Sauvegarde `/srv/biobalance-backups/20260924T230229Z-0cf2b464` restaurée sur un espace isolé : base vérifiée, 104 fichiers traités comparés par taille et SHA-256, 2 magasins et 3 mouvements de stock conservés. Le laboratoire de restauration a été supprimé après réussite. Le mécanisme existant de rotation et de plafond reste actif. Aucun autre site modifié.

## Parcours de test manuel

1. Responsable → groupe → Commandes → Nouvelle commande : choisir le magasin et demander 10 unités. Vérifier que le stock ne change pas. Annuler une première demande avant préparation.
2. Recréer la demande. Admin → Mettre en préparation : l’annulation responsable disparaît. Expédier 6 unités : stock toujours inchangé.
3. Responsable → Non reçue : expliquer le problème. Vérifier l’alerte admin et l’absence d’entrée de stock. Si le colis arrive ensuite, confirmer uniquement les quantités physiques et leurs lots.
4. Recevoir 4 unités sur les 6, en plusieurs lots si nécessaire. Le stock vendable augmente de 4 une seule fois. Les 2 manquantes sont signalées ; les 4 non expédiées restent disponibles.
5. Admin → traiter l’écart : après résolution libérant les manquantes, 6 unités restent à expédier. Préparer le complément, puis contrôler sa réception séparée.
6. Tester un problème général avant expédition : signalement, notification, réponse/résolution et historique. Aucun stock ne change.
7. Vendeur → vente, correction et retour personnels : vérifier stock/points et historique. Les lots épuisés ne sont plus proposés pour une nouvelle vente.
8. Responsable → équipe : son propre accès n’est pas proposé à la modification. Vérifier les invitations et leurs états, le renvoi et la révocation.

## Livraison

Déploiement, signatures, CI et installation à consigner après réalisation. Aucune réinitialisation prévue. La qualification physique complète et iOS restent distinctes des contrôles sur émulateur.
