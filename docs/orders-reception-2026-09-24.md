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
- 287 tests Flutter réussis ; les quatre scénarios dépendant d’un laboratoire restent distincts. Après ajustement visuel final, 75 contrôles ciblés téléphone/paysage 200 % passent. Après les derniers ajustements de garde et de brouillon, 24 tests ciblés passent également. Analyse sans diagnostic ; génération OpenAPI/Dart reproductible.
- 66 contrats HTTP réels validés, puis décodés par le client Dart généré ; deux parcours HTTP/SQLite/PostgreSQL de reprise hors ligne passent (5 opérations, 6 mouvements, 3 révisions, stock 7/1 et version 7, 20 points). Lot manquant : sortie réelle sans entrée artificielle.
- Parcours Android des trois rôles réussi sur émulateur, avec API/PostgreSQL isolés et vérification des stocks, ventes, points et récompenses. Le formulaire de réception est parcouru par produit attendu.
- Reprise Android après arrêt forcé réussie : compte, identifiant et payload conservés ; une seule vente acceptée, stock 7/version 3 et 30 points. Caméra refusée avec recherche manuelle fonctionnelle, puis vidéo H.264 téléchargée et lue hors ligne. Le premier essai local a détecté un sélecteur de test trop strict sur le texte « Caméra indisponible » ; `5922430` corrige uniquement ce test. Le scénario complet relancé passe, et l’analyse finale ne signale aucun problème.
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

Code livré : `3f180baab0d0c27c5ff181a3b8adf35c7bd90463`, poussé sur `codex/biobalance-app`. Backend actif : `biobalance-api:3f180ba` et `biobalance-media:3f180ba`. Les quatre API, les deux workers, Nginx et PostgreSQL sont sains ; HTTPS `/health` répond `200`. Un nouveau contrôle après plus de 30 minutes confirme ces états. Les 24 migrations sont appliquées, aucune migration supplémentaire pour cette version.

Comptages avant/après identiques : 5 comptes, 52 produits, 1 groupe, 2 magasins, aucune vente et 3 mouvements de stock. Aucun effacement ni création de données de démonstration. Le déploiement a remplacé les services progressivement, avec contrôle de santé et rechargement Nginx entre les remplacements.

Configuration privée de retour arrière : `/opt/biobalance/rollback-orders-3f180ba/backend.env`. Les images précédentes `1d312cf` sont conservées. Les anciennes images BioBalance `7bac0ce` et `505795b`, sans conteneur utilisateur, ont été retirées ; aucun nettoyage global Docker et aucun service tiers modifié. Environ 27 Go libres sur le VPS après nettoyage. Un rollback applicatif conserve la base actuelle ; il ne doit pas restaurer une ancienne sauvegarde à la place des nouvelles opérations.

[CI initiale](https://github.com/haider0708/bio-balance-app/actions/runs/36071567888) : backend, Android et iOS non signé réussis. Le journal du job natif confirme le parcours des trois rôles réussi ; la reprise s’est ensuite bloquée à la connexion du driver Flutter avant le démarrage de la phase restaurée. Ce job a été annulé. [CI finale](https://github.com/haider0708/bio-balance-app/actions/runs/36074110338), commit `5922430aa32e7fcefaa55e6426bbd4dc28a00fea` : **quatre jobs réussis** — backend, Android, parcours Android avec reprise après arrêt forcé, compilation iOS non signée. Les sources de l’application et du serveur restent celles de `3f180ba` ; seule une assertion de test change.

### Paquets Android

Les quatre APK et quatre AAB **1.1.9+13** sont signés depuis le même commit propre `3f180ba`. Identifiants, version, certificats existants, manifeste de sécurité, alignement natif et SHA-256 vérifiés. La génération réutilise l’ajustement du compilateur JDK hôte `-XX:-UseLoopPredicate` ; les optimisations de l’application restent actives.

| Application | APK signé | SHA-256 APK |
|---|---|---|
| admin | [1.1.9+13](../.artifacts/releases/builds/20260924T231324Z-android-signed/biobalance-signed.apk) | `9c2f9358f7b5cbb141ca142249ccb2f3d779a7fc98eadcb44ba0db7bb3828010` |
| responsable | [1.1.9+13](../.artifacts/releases/builds/20260924T231754Z-android-signed/biobalance-signed.apk) | `f31490795fddc7563306e79dc6e475aebd17e2258069fce2ef20f36c822251b2` |
| vendeur | [1.1.9+13](../.artifacts/releases/builds/20260924T232224Z-android-signed/biobalance-signed.apk) | `92020e15db51427b32b6c2a8ad1753be8a6acdf23d5dd96f519b4f9de9f478a6` |
| vendeur2 | [1.1.9+13](../.artifacts/releases/builds/20260924T232654Z-android-signed/biobalance-signed.apk) | `12ca07eff34e5427963e6321ab1f8d3a4057de3fffdf7cbe17b1107e160883ed` |

Le registre local `.artifacts/orders-release/verified-artifacts.json` contient les chemins, empreintes APK/AAB, identifiants et commit ; chaque répertoire de construction possède son manifeste et ses preuves de signature. Les journaux de tests, restauration et déploiement sont sous `.artifacts/orders-*`.

### Samsung — installation en attente

Le Samsung n’est actuellement visible ni en USB ni en débogage sans fil ; l’ancienne adresse sans fil est inaccessible. **La version 1.1.9 n’a donc pas été installée sur le téléphone.** La dernière installation confirmée reste 1.1.8+12. Les quatre mises à jour sont prêtes pour `adb install -r --no-incremental`, avec contrôle de l’identité du téléphone et conservation des UID. Aucune désinstallation, aucun effacement et aucune réinitialisation ne sont requis.

Les tests sur émulateur et les captures contrôlées ne remplacent pas le parcours tactile de cette version sur le Samsung. Qualification physique complète, publication Apple/Google et pilote restent distincts ; aucune signature Apple ou acceptation en magasin d’applications n’est revendiquée.
