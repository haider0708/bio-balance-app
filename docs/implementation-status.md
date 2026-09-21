# État de l’implémentation — 21 septembre 2026

L’application est en développement et n’est pas encore qualifiée pour une diffusion en production. Ce document distingue les fonctionnalités codées des vérifications réalisées.

## Fonctionnalités présentes

- Flutter Android/iOS, français, thème BioBalance et Inter local, navigation par rôle, sélection de magasin, formulaires et états d’erreur.
- Identité email/mot de passe, invitations, récupération, sessions révocables, MFA TOTP administrateur et provisionnement privé.
- Organisations, magasins, équipes, catalogue, import CSV avec validation préalable et configuration des prix/seuils/points.
- Stock par lot/péremption, réceptions, ventes, corrections, retours, dommages, ajustements, alertes de stock et de péremption.
- Transactions PostgreSQL avec contraintes, RLS, versions, idempotence, journaux de stock/points/audit et protection des historiques.
- Commandes et livraisons partagées, réception unique, suivi des quantités réellement reçues et des reliquats.
- Points à la première synchronisation acceptée, réservations, remise de récompenses et débit produit, soldes négatifs et classement mensuel.
- SQLite avec outbox durable, brouillons, reprise après arrêt, isolation compte/magasin, résolution des saisies rejetées et migration avec file peuplée.
- Synchronisation différentielle des lots/configurations ; collections autorisées actualisées et rechargement complet si catalogue modifié ou backlog important.
- Articles/vidéos, téléversement par fragments, traitement média, publication contrôlée, cache de formation et téléchargement vidéo.
- Annonces du responsable, notifications opérationnelles, enregistrement push lié à une session valide, historique consultable dans l’application.
- Vue administrateur, historiques paginés de ventes/points/audit/mouvements et export des lignes affichées.
- Docker Compose VPS, deux API, workers séparés, Nginx, migrations, sauvegarde locale, restauration isolée, CI et scénario k6.

## Vérifications réalisées localement

| Vérification | Résultat constaté |
|---|---|
| Compilation TypeScript | Réussie |
| Tests domaine backend | 6 réussis |
| Tests PostgreSQL réels avec rôle restreint | 14 réussis (étape 1) |
| Tests Flutter de reprise, migration et dispositions d’écran | 16 réussis ; parcours HTTP réel exécuté séparément et réussi |
| Build Android debug | APK produit ; les dernières modifications doivent encore être vérifiées sur l’application exécutée |
| Sauvegarde/restauration isolée | Réussie sur les données de développement ; archive média vide, à compléter avec des médias réels traités |
| OpenAPI et génération Dart | Exécutés, 40 méthodes de transport générées |
| Images Docker et émulateur | Vérifications commencées ; résultat final à confirmer |

Un passage des tests PostgreSQL a expiré pendant une forte saturation mémoire de l’hôte par les builds Android. Après arrêt des anciens daemons de compilation devenus inutiles, les 12 tests ont réussi sans allonger leur délai.

## Travail restant avant acceptation

- Terminer la vérification des images conteneur, de l’application exécutée et de la restauration avec des médias non vides.
- Compléter les parcours UI automatisés des trois rôles ; vérifier les permissions retirées pendant qu’un écran secondaire est ouvert, les erreurs de stockage, le téléchargement interrompu et les reprises de téléversement sur téléphone.
- Compléter les détails UX restants : restauration automatique de certains brouillons de formation/annonce, association produit dans l’éditeur de formation, préférences/images facultatives, réception entièrement manquante et commande préremplie depuis une alerte.
- Compléter les schémas de requête/réponse OpenAPI encore génériques et la couverture des contrats.
- Exécuter tests caméra/push, accessibilité, rotation et stabilité mémoire sur Android/iOS physiques ; compiler iOS sur macOS et produire les builds signés.
- Préparer les données de charge représentatives, exécuter 100 req/s et le pic 200 req/s sur le VPS de référence ; mesurer réellement démarrage, recherche, persistance et fluidité. Aucune de ces performances n’est encore revendiquée.
- Renseigner VPS/domaine/SMTP/Firebase/APNs/signatures, valider renouvellement TLS/supervision, puis effectuer le pilote et corriger ses retours.

Les sauvegardes hors VPS, la haute disponibilité, les abonnements payants, l’admin web, WhatsApp et les classements hors magasin restent reportés conformément au périmètre approuvé.

## Plan séquentiel — registre des étapes

La base existante est enregistrée par le commit `2b098ed`. Les douze étapes restent séquentielles ; une vérification externe indisponible n’est jamais comptée comme réussie.

### Étape 1 — Cohérence du stock hors ligne

Implémentation et vérifications locales terminées : commit `7f25895`.

- Projection métier `StockProjection`/`LotMovement`, hors widgets : réceptions, ventes, corrections, retours, dommages et ajustements. Nouveau lot v1 puis réception v2 ; dommage +2 versions et deux compartiments.
- SQLite v3 conserve les identifiants et octets des anciens payloads, ajoute dépendances, ressources touchées, incertitude d’envoi, résultat d’acquittement et date de nouvelle tentative. Commande, effets, dépendances et fin du brouillon sont atomiques.
- Les dépendances bloquent uniquement les opérations concernées. La résolution vérifie la fermeture des dépendances et conserve les saisies originales ; aucune opération au résultat incertain n’est assimilée à une saisie jamais envoyée.
- Délai exponentiel avec aléa, plafond cinq minutes et `Retry-After`. Un marqueur d’envoi est persisté avant le réseau. Les erreurs d’accès suivent le flux d’authentification, les refus métier restent visibles.
- Protocole de commande v2 et lecture de statut compatible v1, curseur validé et versions affectées. Le cache et les suppressions d’effets acquittés sont appliqués ensemble. Correction supplémentaire : les permissions sont des métadonnées, pas une collection d’entités.
- Migration PostgreSQL additive `202609210005_sync_pages` : pages figées dans la transaction du snapshot, jetons liés au compte/magasin/droits, expiration cinq minutes, accès revérifié à chaque page et redémarrage côté mobile après expiration.
- Validation : compilation TypeScript ; 6 tests métier ; 14 tests PostgreSQL ; 16 tests Flutter (10 reprise/migration et 6 dispositions). Le parcours `npm run test:mobile-sync` exécute Flutter/SQLite contre Nest/HTTP/PostgreSQL isolés, perd une réponse acceptée et une réponse snapshot, ferme/réouvre SQLite, puis vérifie 5 opérations uniques, 6 mouvements, 3 révisions, stock vendable 7, endommagé 1, version 7 et 20 points.
- Le test HTTP est ignoré par `flutter test` sans environnement de test et exécuté explicitement par son script ; ce saut n’est pas un succès. La CI prépare désormais cet environnement.
- Limites : fermeture/réouverture du fichier SQLite testée ; arrêt brutal par le système mobile, manque d’espace réel et mesures sur appareils restent dans les étapes 9–10. Aucun processus Flutter de débogage n’était disponible pour un rechargement à chaud ; analyse et tests ont été utilisés.

| Étape suivante | État |
|---|---|
| 2. Accès et sessions | Implémentation et vérification locale terminées (voir registre ci-dessous) |
| 3. Ventes et stock UX | Implémentation et vérification locale terminées (voir registre ci-dessous) |
| 4. Commandes/livraisons | À réaliser |
| 5. Onboarding/images | À réaliser |
| 6. Brouillons et transferts | À réaliser |
| 7. Contrats et nettoyage | À réaliser |
| 8. Notifications/workers | À réaliser |
| 9. Parcours complets | À réaliser |
| 10. Performances/appareils | À réaliser ; appareils physiques requis pour les mesures correspondantes |
| 11. Déploiement/reprise | À réaliser ; dépôt distant/VPS/DNS requis pour les vérifications externes |
| 12. Versions signées/pilote | En attente des comptes de signature et participants ; pilote de deux semaines requis |

### Étape 2 — Accès et reprise de session

Commit : `816eb24`.

- États explicites de session : authentifiée, hors ligne, expirée, désactivée, accès magasin retiré et déconnectée.
- Transport Dio séparé des fichiers générés : captures immuables du compte, des credentials et de la génération ; les réponses tardives et les réponses antérieures à une perte d’accès sont rejetées avant d’entrer dans le cache. Les transferts média capturent aussi leur contexte.
- Accès retirés conservés par compte dans SQLite ; sélectionner un magasin en cache ne réactive pas un accès refusé. Une lecture serveur autorisée est nécessaire pour le rétablir.
- Navigation protégée réinitialisée après sauvegarde des brouillons ; les formulaires génériques, lignes de vente et formations conservent les champs en cours. Si l’écriture locale échoue, la route reste en mémoire derrière un écran bloquant avec possibilité de réessayer.
- Garde avant confirmation des ventes, retours et opérations ; arrêt des transferts sur fermeture ; suppression des notifications après déconnexion sans bloquer celle-ci. La révocation serveur reste une tentative réseau, tandis que credentials et état local sont effacés immédiatement après sauvegarde locale.
- Création d’invitation et contrôle de permission dans la même transaction. Les transactions de magasin vérifient également la session courante. Le code `STORE_ACCESS_REVOKED` distingue un magasin retiré d’une action interdite dans un magasin encore accessible.
- Validation locale : compilation TypeScript ; 15 tests PostgreSQL ; 6 nouveaux tests Flutter couvrant réponses tardives (même compte/nouveau compte), déconnexion avec réseau/push bloqués, accès retiré, conservation de l’outbox, formulaire ouvert et panne d’écriture, expiration explicite. Le parcours réel HTTP/SQLite/PostgreSQL de l’étape 1 continue de réussir.
- Les notifications réelles Firebase/APNs restent une vérification externe de l’étape 8 ; les tests présents utilisent un service contrôlé.

### Étape 3 — Ventes et interface de stock

- Sélection du lot valide avec stock positif et péremption la plus proche ; les lots sans disponibilité restent sélectionnables pour enregistrer une vente réelle et afficher l’avertissement d’écart.
- Le vendeur peut renseigner lot/péremption directement dans l’éditeur de vente. Déclaration déterministe du lot et vente dans la même transaction serveur : métadonnées v1 puis sortie v2, aucune réception artificielle. Les déclarations restent dans le brouillon et sont projetées hors ligne.
- Expiries normalisées côté domaine (formats français ou ISO, fin du mois quand seul le mois est saisi). Dates civiles et horodatages tunisiens UTC+1 affichés distinctement ; contrôles des bornes et années bissextiles.
- Filtres stock faible, écart, péremption dans les 30 jours inclus, et produits périmés ; les lots épuisés ne produisent pas de fausse alerte de péremption.
- Corrections locales refusées si elles supprimeraient des unités déjà retournées. Les détails choisissent la révision locale/serveur actuelle, se rafraîchissent après correction, montrent vendeur/lots et quantités encore retournables.
- Validation : 16 tests PostgreSQL (dont déclaration manquante, sortie unique, rollback de lot expiré et identité invalide), 5 tests Dart de dates/sélection/filtres/révisions, 2 tests supplémentaires d’éditeur/correction. Le script HTTP réel exécute désormais deux parcours, dont une vente par un vendeur sans permission de gestion du stock.
- La création du catalogue global reste réservée à l’administrateur. La caméra physique et les essais sur appareils restent prévus aux étapes 9–10 ; le parcours d’éditeur automatisé utilise la saisie manuelle.
