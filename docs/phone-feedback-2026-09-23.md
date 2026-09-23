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

- Analyse Flutter et compilation TypeScript sans erreur ; format API validé ; 105 tests backend réussis (domaine, transactions, permissions, emails, notifications et médias).
- 220 tests Flutter réussis. Quatre tests dépendant de fixtures sont ignorés dans cette commande : le contrat HTTP et les deux parcours de synchronisation sont exécutés séparément et réussissent ; le test de média déployé n’est pas compté comme réussi ici.
- Génération du contrat/client reproductible sans différence après régénération ; 60 endpoints HTTP vérifiés avec décodage/réencodage Dart ; synchronisation réelle HTTP/SQLite/PostgreSQL réussie, y compris réception → vente → dommage → correction → retour et lot manquant sans réception artificielle.
- Parcours Android natif administrateur/responsable/vendeur réussi sur émulateur API 36 avec API et base isolées. Assertions finales : stock 21, points 20, réserve 0, trois révisions, récompense remise et livraison reçue.
- Régression du cache photo démontrée : les deux tests échouent avec l’ancienne ligne et réussissent avec la correction.
- Captures de 28 écrans, contrôles portrait et paysage à 200 %, révision visuelle des formulaires, commandes et listes avec données.
- Sauvegarde VPS préalable réussie ; restauration isolée et validation de 104 fichiers média traités par taille et SHA-256 réussies.

Source applicative : `a9fd5761295e14d42d03b13c984187fa05019adb`, poussée sur `codex/biobalance-app`. APK et AAB 1.1.1+5 construits depuis cette révision propre, signés avec les identités existantes ; certificats, manifeste de sécurité, alignement ZIP/ELF 16 Kio et absence de DWARF incorporé vérifiés. Empreinte SHA-256 APK : `28fbb8686c73f306c720e0e0421ccfaa77d400c5fea8972ba1e83a7c74a7130a`.

## Livraison vérifiée

Backend déployé sous `biobalance-api:a9fd576` (quatre instances) et `biobalance-media:a9fd576` ; huit services sains, Nginx validé/rechargé, HTTPS public et refus des accès anonymes vérifiés. Les vérifications opérateur passent par les services serveur avec les contrôles de droits et audits existants ; elles ne sont pas présentées comme une connexion HTTP avec votre nouveau mot de passe.

Les cinq commandes sont ouvertes trois fois chacune : trois à préparer, une expédiée et une terminée. Les 51 miniatures sont vérifiées par taille et SHA-256. La base conserve exactement deux groupes, cinq magasins, huit comptes, 100 ventes, 394 mouvements, 117 écritures de points et 51 produits ; empreintes ventes/stock/journal inchangées. Aucun mot de passe existant n’est changé par cette livraison.

La sauvegarde `20260923T142557Z-3e77c1d4` et ses 104 médias ont été restaurés et vérifiés. Copies de restauration et archives de transfert retirées ; sauvegardes gérées de 13 Mio avec rétention/plafond existants. Les timers sauvegarde, surveillance et TLS sont actifs, aucun job échoué/bloqué/en retard ; 26 Gio libres sur le VPS. Images précédentes et configuration privée conservées pour retour arrière. Aucun service d’un autre site modifié.

Samsung SM-G975F : mise à jour 1.1.1+5 installée par remplacement sans effacement ; UID et date d’installation d’origine identiques. Lancement confirmé, aucun message fatal Flutter/Android dans le nouveau processus. Le fichier APK temporaire a été retiré du téléphone. Une validation visuelle manuelle complète sur votre appareil reste distincte de ce contrôle d’installation.

[Preuves et empreintes des journaux](../tests/deployment/phone-feedback-evidence-2026-09-23.json). GitHub : backend et iOS non signé réussis ; Android et parcours Android encore en cours au moment de ce relevé. Les essais de laboratoire ne remplacent pas la qualification physique des performances ni celle d’iOS.
