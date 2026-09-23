# BioBalance — Spécification fonctionnelle approuvée

Référence : plans d’implémentation du 21 septembre et de refonte du 23 septembre 2026. L’état réel du logiciel et les validations se trouvent dans [implementation-status.md](implementation-status.md).

## Périmètre

Une application Flutter Android/iOS, en français, pour les vendeurs, responsables et l’administrateur BioBalance. Cible initiale : 500 magasins et 5 000 comptes. Les partenaires sont des détaillants. Le catalogue global et les formations sont administrés par BioBalance. Chaque organisation partenaire possède un ou plusieurs magasins ; chaque magasin conserve son équipe, ses stocks, prix, seuils, points et récompenses.

Les abonnements payants, le web admin, WhatsApp, les classements régionaux/nationaux et les sauvegardes hors serveur sont reportés. L’application ne réalise pas de paiement et ne gère pas de commandes de consommateurs.

## Accès et mise en route

- Trois rôles : administrateur BioBalance, responsable de groupe, vendeur affecté aux magasins. Tout responsable possède la même autorité sur tous les magasins de son groupe ; aucun rôle propriétaire distinct. BioBalance invite les nouveaux responsables ; activation puis création de leur groupe via une autorisation à usage unique. Inviter ne crée plus de groupe. Les responsables invitent d’autres responsables dans le groupe existant ou des vendeurs dans les magasins explicitement choisis. Connexion personnelle par email et mot de passe, récupération de compte, invitations expirables, sessions révocables et MFA administrateur.
- Les permissions proviennent des appartenances à une organisation et à un magasin. Un responsable peut également vendre. Un vendeur corrige uniquement ses ventes ; le responsable et l’administrateur corrigent les ventes des magasins autorisés.
- Le guide reprend après interruption : compte, groupe, premier magasin, équipe, stock initial, configuration des prix/seuils/points. Nom, adresse et ville sont requis ; téléphone et image sont facultatifs.
- La progression du guide est dérivée des données enregistrées. « Je travaille seul » et « Pas de stock initial » sont des choix explicites ; les produits portés configurés à zéro point demandent confirmation.
- L’administrateur commence au réseau, le responsable au groupe, le vendeur à son magasin autorisé. Un seul sélecteur recherchable de groupe apparaît en haut à gauche : changer de groupe revient à son résumé. Un magasin s’ouvre depuis la liste du groupe ; il n’y a pas de second menu déroulant. Les vendeurs affectés à plusieurs magasins choisissent parmi leurs seuls magasins autorisés. Le bouton Retour suit les pages, onglets et périmètres précédents. Les brouillons et opérations ne changent jamais de compte ni de magasin.
- Désactiver ou retirer un accès conserve les ventes, mouvements et identités historiques.

## Ventes, lots et exactitude

- Vente directe réalisée en magasin : scanner ou chercher, vérifier les quantités, prix et lots, enregistrer. Plusieurs produits et allocations de lots sont autorisés.
- Les prix sont calculés exactement en millimes entiers ; JSON utilise une chaîne décimale pour éviter toute perte de précision. Affichage `49,900 TND`, dates `DD/MM/YYYY`.
- Lots identifiés par magasin, produit, numéro de lot et date de péremption. Quantités entières ; une péremption au mois devient le dernier jour du mois.
- Le lot valide avec quantité positive expirant le plus tôt est proposé, avec choix du lot effectivement remis. Stock périmé ou endommagé exclu du disponible, mais conservé dans l’historique.
- Le vendeur peut saisir un lot et sa péremption manquants pendant la vente. Métadonnées du lot et vente sont atomiques ; aucun stock entrant artificiel ni produit global créé par le vendeur.
- Filtres disponibles : stock faible, écarts, péremption dans les 30 jours et lots expirés. Les dates civiles de péremption sont distinctes des horodatages affichés en heure tunisienne.
- Une vente réelle dépassant le stock enregistré est conservée. Elle entraîne un écart à régulariser, sans inventer une réception.
- Corrections avec motif, auteur, valeurs précédentes et compensations. Les retours partent de la vente d’origine et ne dépassent pas les unités encore retournables. Seules les unités vendables rejoignent le stock vendable.
- Mouvements enregistrés pour ouverture, réception, vente, correction, retour, dommage, ajustement et cadeau. Aucune suppression silencieuse d’historique.

## Points et récompenses

- Chaque magasin fixe les points par unité de chaque produit ; une configuration absente vaut zéro et doit être visible au responsable.
- **Le barème de la première synchronisation réussie fait foi.** Les points affichés hors connexion sont une estimation. Les répétitions retournent le résultat accepté ; elles ne recalculent pas les points.
- Une correction conserve le barème déjà accepté pour les produits existants. Un produit ajouté à la correction utilise le barème de son acceptation.
- Les retours retirent les points correspondants. Un solde négatif compense les gains futurs et ne constitue pas une dette en argent.
- Demande de récompense en ligne : réservation des points. Déduction définitive après remise physique et confirmation du responsable. Annulation/refus libère la réservation.
- La remise revalide points et disponibilité du produit. Une demande devenue non finançable reste en attente. Un cadeau lié à un produit sort du stock sans attribuer de points de vente.
- Classement mensuel par magasin, selon son fuseau horaire, sur les points gagnés nets. Les dépenses de récompenses ne diminuent pas le classement ; les ex æquo partagent leur rang.

## Réapprovisionnement

- Seuil par produit/magasin, alerte à quantité inférieure ou égale, rupture distincte à zéro. L’alerte reste visible et n’est pas répétée à chaque vente.
- Le responsable commande à tout moment. BioBalance prépare et expédie ; chaque livraison physique possède un identifiant partagé.
- L’expédition ne change pas le stock du magasin. La réception renseigne les quantités réelles, lots, dates et écarts.
- Une réception totalement manquante accepte zéro unité avec motif et confirmation explicite. Le reste à expédier déduit les unités effectivement reçues et celles encore en transit ; les suivis gardent leurs propres identifiants.
- Une livraison ne peut pas être réceptionnée deux fois. Les livraisons complémentaires utilisent de nouveaux identifiants. Les quantités manquantes restent visibles.

## Formation et communication

- Articles et vidéos : brouillon, prévisualisation, publication, modification et archivage par BioBalance. Un média doit être traité avec succès avant publication.
- Images magasin/récompense gérées par leur responsable autorisé, images catalogue par BioBalance ; JPEG/PNG jusqu’à 10 Mo, redimensionnés et attachables après traitement uniquement.
- Téléversement vidéo par fragments, position de reprise confirmée côté serveur. Consultation et téléchargement choisi pour usage hors connexion.
- Notifications automatiques opérationnelles : responsables et administrateur uniquement. Les vendeurs reçoivent les annonces explicitement envoyées par leur responsable.
- Le message et son audience/magasin sont visibles avant envoi. Centre de notifications hébergé sur le VPS et emails d’activation/récupération. Firebase est retiré ; les alertes OS lorsque l’application est fermée sont reportées.
- Catalogue maintenable par BioBalance, import CSV validé, supervision des magasins, audit et exports contrôlés.

## Hors connexion

| Disponible après téléchargement | Brouillon jusqu’à connexion | Connexion requise |
|---|---|---|
| Produits/stock en cache, ventes, corrections autorisées, réceptions de livraisons téléchargées, formation téléchargée | Commandes, annonces, éditions de formation, demandes de récompenses | Première connexion/activation, accès équipe, publication/barèmes, réservation et remise de récompenses |

La modification locale et sa commande sortante sont enregistrées ensemble. Les accusés serveur et la suppression des effets provisoires sont réconciliés ensemble. Les opérations suivent leur ordre de dépendance ; identifiants stables et contrôle de version empêchent les doublons et les écrasements silencieux.

États explicites : **enregistrée sur ce téléphone**, **en attente de synchronisation**, **synchronisée**, **à vérifier**. Déconnexion, retrait de permissions, expiration de session et changement de compte ne suppriment pas les opérations en attente. Les conflits restent visibles et doivent pouvoir être repris avec le bon compte et magasin.

## Interface et exploitation

Identité officielle : logo BioBalance, vert `#6ABE4E`, boutons vert foncé contrastés, Inter local, surfaces claires. Cibles tactiles 48 dp, texte principal 16 sp, texte secondaire 14 sp, paysage et agrandissement 200 %, alternatives au scan et permissions demandées au moment utile.

Toutes les fonctionnalités doivent couvrir chargement, absence de données, recherche vide, cache hors ligne, erreurs récupérables, permissions refusées, session expirée et conflits. Les formulaires conservent leurs valeurs.

L’application, PostgreSQL et les médias sont hébergés sur un VPS. Aucun service Firebase n’est utilisé. La boîte de notifications est disponible dans l’application ; un transport OS en arrière-plan pourra être choisi séparément. Les sauvegardes locales sont vérifiées par restauration isolée ; elles ne couvrent pas la perte du serveur entier.

### Lots absents lors d’une vente

Un vendeur peut déclarer le numéro de lot et sa date de péremption pendant la saisie. Le serveur crée uniquement les métadonnées manquantes puis enregistre la sortie réelle dans une transaction unique. Une quantité négative produit un écart à vérifier ; aucune entrée fictive ne compense la vente. Les produits globaux restent administrés par BioBalance. La proposition FEFO privilégie les lots valides ayant du stock positif ; la péremption est évaluée à la date de la vente d’origine, y compris lors d’une correction.

### Ergonomie mobile — précision du 22 septembre 2026

L’interface utilise des lignes compactes et des indicateurs simples. Les options moins fréquentes sont regroupées dans Plus. Les petites largeurs regroupent Équipe/Catalogue dans ce menu ; les textes agrandis et les écrans bas utilisent une navigation verticale défilante. Les responsables disposent d’une page de recherche dédiée aux prix, points et seuils. Les sélecteurs sont recherchables et les formulaires partagés gardent leur validation visible au-dessus du clavier. Voir [les parcours et captures](mobile-ux-2026-09-22.md).


## Refonte du 23 septembre : résumés et présentation

Navigation : réseau (Accueil, Groupes, Commandes, Catalogue), groupe (Résumé, Magasins, Équipe, Commandes), magasin responsable (Accueil, Stock, Commandes, Plus), vendeur (Accueil, Ventes, Récompenses, Formation). Formation globale, invitations et compte restent dans le menu d’administration. Un changement de contexte sauvegarde les brouillons avant navigation ; son échec conserve l’éditeur. Les réponses obsolètes ne peuvent alimenter le nouveau compte/groupe/magasin.

Les tableaux de bord affichent leur périmètre, période et fraîcheur. Les dates suivent Africa/Tunis : aujourd’hui, sept derniers jours, mois courant ou intervalle de 366 jours maximum. L’administration commence au mois, le vendeur à aujourd’hui. Les ventes nettes utilisent les lignes corrigées moins les unités retournées, imputées à la date et au vendeur de la vente initiale. Le nombre de ventes enregistrées inclut les ventes entièrement retournées. Stock, commandes/livraisons attendues, récompenses et points relèvent de la situation actuelle. Les opérations locales en attente ne sont pas incluses dans les totaux acceptés. Aucun bénéfice, encaissement ou classement inter-magasins n’est inventé.

Les photos produit conservent l’emballage entier. Catégorie, gamme, format, description, conseils, ingrédients, précautions, sources et état de complétude appartiennent au catalogue global. Prix de référence manquant, zéro explicitement configuré et tarif de démonstration sont distincts. Une modification globale ne remplace pas les prix fixés par un magasin. Les informations non vérifiées restent absentes.

Le thème central est blanc #FFFFFF, menthe #F1F8F4, émeraude #146C43, accent #6ABE4E et texte #17231C, police Inter locale, icônes Lucide. Navigation défilante si texte agrandi, cibles 48 dp, animations courtes désactivées selon les préférences d’accessibilité. Les captures et limites de qualification sont dans [le registre de refonte](redesign-2026-09-23.md).


## Retour Samsung — 1.1.1

Les codes de récupération contiennent huit lettres/chiffres majuscules, présentés en cases avec collage complet. Une nouvelle demande remplace le précédent code ; le succès renvoie directement à la connexion. Les invitations sont uniques par personne/groupe : le renvoi remplace l’ancien code et la modification d’un membre existant passe par sa fiche d’accès.

Les commandes sont regroupées en « À préparer », « Expédiées / à réceptionner » et « Terminées ». Leur détail indique le groupe, le magasin, les quantités demandées/reçues/en route/restantes et les réceptions. La liste des ventes nomme magasin et vendeur. Les formulaires utilisent un défilement de page unique et des actions accessibles avec le clavier ouvert.
