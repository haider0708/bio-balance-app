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
| Tests PostgreSQL réels avec rôle restreint | 20 réussis + 3 tests de traitement média réel |
| Tests Flutter de reprise, migration et dispositions d’écran | 49 réussis (48 dans la passe complète, puis un cas supplémentaire ciblé) ; 2 parcours HTTP réels et 1 test de contrats Dart exécutés séparément et réussis |
| Build Android debug | APK reconstruit avec les ressources natives et liens de l’étape 6 ; exécution sur téléphone encore à vérifier |
| Sauvegarde/restauration isolée | Réussie sur les données de développement ; archive média vide, à compléter avec des médias réels traités |
| OpenAPI et génération Dart | 44 endpoints vérifiés sur HTTP réel ; 178 schémas Dart typés générés et aller-retour JSON validé |
| Images Docker et émulateur | Vérifications commencées ; résultat final à confirmer |

Un passage des tests PostgreSQL a expiré pendant une forte saturation mémoire de l’hôte par les builds Android. Après arrêt des anciens daemons de compilation devenus inutiles, les 12 tests ont réussi sans allonger leur délai.

## Travail restant avant acceptation

- Terminer la vérification des images conteneur, de l’application exécutée et de la restauration avec des médias non vides.
- Compléter les parcours UI automatisés des trois rôles ; vérifier les permissions retirées pendant qu’un écran secondaire est ouvert, les erreurs de stockage, le téléchargement interrompu et les reprises de téléversement sur téléphone.
- Vérifier les transferts vidéo et liens de compte sur appareils natifs ; brouillons, association produit, aperçu et reprise des transferts sont implémentés et testés localement.
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
| 4. Commandes/livraisons | Implémentation et vérification locale terminées (voir registre ci-dessous) |
| 5. Onboarding/images | Implémentation et vérification locale terminées (voir registre ci-dessous) |
| 6. Brouillons et transferts | Implémentation et vérification locale terminées (voir registre ci-dessous) |
| 7. Contrats et nettoyage | Implémentation et vérification locale terminées (voir registre ci-dessous) |
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

Étape 3 : commit fonctionnel `a57026b`. La passe complète a relevé une attente obsolète dans le nouveau test d’éditeur (elle demandait à tort un brouillon vide). L’assertion vérifie maintenant la conservation du lot saisi et l’absence de stock ajouté avant confirmation de vente. La suite complète réussit : 29 tests Flutter ; les 2 parcours HTTP réels sont exécutés séparément et réussissent.


### Étape 4 — Commandes et livraisons

Commit : `9d83e8f`.

- Les alertes de stock faible/rupture ouvrent un brouillon avec le produit concerné, le stock, le seuil et toutes les unités déjà commandées. Compte, magasin et identifiant de commande restent stables ; une transmission incertaine reprend ses quantités originales.
- Calcul de fulfillment partagé côté serveur : quantités effectivement reçues, en transit, restant à expédier et restant à recevoir. Le total d’approvisionnement tient compte de toutes les commandes ouvertes, indépendamment de la limite d’historique. Un nouvel endpoint expose la version et les restes utilisés par l’éditeur d’expédition.
- Réception entièrement manquante : motif obligatoire côté serveur, confirmation explicite côté mobile, historique conservé, aucun mouvement de stock. Réceptions concurrentes/rejouées restent protégées par l’identité unique de livraison. Une réception en attente sur le téléphone désactive une seconde saisie et conserve son état de synchronisation.
- Brouillons de réception incluant motif et choix zéro unité ; sauvegarde avant perte d’accès et suppression atomique avec la commande locale. Les tentatives en ligne conservent leur identifiant sur erreur temporaire ou accès expiré.
- Migration additive `202609210006_delivery_fulfillment` : index magasin/commande sur les livraisons. Contrat et transport régénérés.
- Validation locale : compilation TypeScript, 17 tests PostgreSQL, 32 tests Flutter et analyse Dart sans erreur. Les 2 parcours HTTP/SQLite/PostgreSQL réussissent séparément. Nouveaux tests : stock/seuil/approvisionnement affichés, contexte magasin du brouillon, motif et annulation de confirmation zéro unité, blocage de double réception locale ; réception vide/rejouée et remplacement complet dans PostgreSQL.
- Aucune livraison physique ni notification réelle n’a été simulée comme preuve de production ; les essais sur téléphones et le pilote restent prévus aux étapes correspondantes.


### Étape 5 — Guide, paramètres et images

Commit : `c5d4570`.

- Progression calculée à partir du magasin enregistré, des membres/invitations, des réceptions et des produits effectivement portés par le magasin. Les choix « Je travaille seul » et « Je n’ai pas de stock de départ » sont explicites et versionnés. Une valeur historique `onboardingStep=5` ne masque plus les étapes manquantes.
- Les configurations à zéro point exigent une confirmation explicite ; les configurations positives et les taux déjà acceptés des ventes restent inchangés. Le guide peut être quitté/repris depuis Plus ; un magasin nouvellement créé est sélectionné et ouvre le guide.
- Modification versionnée du nom, adresse, ville, téléphone et image du magasin ; édition/archivage des récompenses, produit lié, quantité et image ; images catalogue réservées à BioBalance.
- Migration additive `202609210007_store_setup_media` : choix/progression, version du magasin, confirmation zéro point, finalité et portée des médias, empreintes et taille traitée. Accès aux téléversements revérifié dans la transaction ; un média d’un autre magasin/finalité ou encore en traitement ne peut pas être attaché.
- JPEG/PNG limités à 10 Mo. Traitement isolé du worker principal, signature/dimensions vérifiées, image redimensionnée sans agrandissement (maximum 1600 px), métadonnées retirées, checksum et longueur finale enregistrés. Les transferts capturent le compte/magasin, se reprennent par identité de contenu et conservent le fichier d’origine pour les relectures du dernier fragment. Seul un média traité est proposé dans le formulaire.
- Icônes Android adaptatives et iOS, écrans de lancement Android/iOS, dérivés du logo BioBalance fourni ; script de génération versionné (Pillow).
- Validation locale : 18 tests PostgreSQL ; 2 tests supplémentaires avec de vraies images et ffmpeg/ffprobe (2400×1200 → 1600×800, checksum, refus inter-magasin, dernier fragment répété, fichier altéré) ; 34 tests Flutter ; 2 parcours HTTP/SQLite/PostgreSQL ; analyse Dart sans erreur ; contrat régénéré (42 routes). CI mise à jour pour exécuter le traitement média, mais aucun lancement distant de CI n’est revendiqué.
- Environnement local : ffmpeg extrait dans `.tooling/ffmpeg` sans installation système ; exécutables et bibliothèques ignorés par Git. Le conteneur média installe ffmpeg. Les vérifications de signature et les essais iOS/macOS/appareils restent des étapes ultérieures.

- Build Android debug final de l’étape 5 réussi (icônes et ressources natives compilées) ; 6 tests domaine backend toujours réussis. Avertissements non bloquants du toolchain : migration future du plugin Firebase vers Kotlin intégré et versions de métadonnées SDK. Ils ne sont pas présentés comme des échecs de compilation ni comme une vérification sur appareil.

### Étape 6 — Brouillons, transferts et liens de compte

Commit : `8e3f201`.

- Brouillons de formation avec identité stable, produits associés, visibilité, source du fichier et état du média ; restauration automatique par compte. Aperçu commun au lecteur, texte HTML nettoyé/décodé, recherche et filtre produit. Comparaison explicite avec la version serveur en cas de modification concurrente, sans perdre le brouillon.
- Annonces avec brouillon attaché au magasin d’origine, confirmation du magasin et de l’audience, identifiant stable et message figé après transmission incertaine. Rejouer une soumission ne crée ni notification ni audit supplémentaire.
- Migration additive `202609210008_content_submissions` appliquée en développement et test : empreinte/résultat des soumissions de contenu, RLS par auteur, empreinte/audience effectivement notifiée des annonces. Les historiques existants sont conservés. Une réponse perdue retrouve le résultat accepté ; une modification locale ultérieure utilise la version de cette acceptation.
- Reprise des téléversements par identité, taille et SHA-256 du fichier ; dernier fragment accepté rejouable après traitement. Calcul des empreintes dans un isolate Dart, annulation des transferts à la fermeture. Publication interdite pour une vidéo non traitée et pour un article vide.
- Téléchargement par plages HTTP et `If-Range`, manifeste et fichier partiel persistants ; traitement d’un serveur ignorant Range, vérification de longueur et SHA-256 avant disponibilité hors ligne, rejet d’une réponse d’un ancien compte. Métadonnées protégées, ETag et lecture vidéo depuis le fichier vérifié ; pause en arrière-plan et destruction du lecteur en quittant l’écran.
- Liens `biobalance://activate` et `biobalance://recover`, validation du chemin/token et saisie manuelle maintenue. Une session ouverte demande une déconnexion avec conservation du travail avant ouverture du lien. Configuration native Android/iOS ajoutée ; hôte HTTPS optionnel strictement limité au domaine configuré.
- Vérifications : 20 tests PostgreSQL, 6 tests domaine, 3 tests de médias réels avec ffmpeg/ffprobe (dont vidéo H.264, publication contrôlée, plage HTTP exacte, checksum et refus après archivage). 45 tests Flutter : reprise de transferts, checksum altéré, réponse tardive, idempotence, restauration des brouillons, liens et aperçu, paysage/clavier/texte 200 %. Les 2 parcours Nest/HTTP/PostgreSQL/SQLite passent séparément. Analyse Dart sans erreur, TypeScript compilé, contrat régénéré avec 44 routes.
- Limites : décodage/lecture vidéo hors ligne, permissions natives et ouverture des liens sur appareils Android/iOS à vérifier lors des étapes 9–10 ; le test de traitement et de téléchargement n’est pas une preuve de lecture sur téléphone. L’association HTTPS universelle exige le domaine détenu et ses fichiers d’association ; configuration externe non fournie. Aucun test FCM/APNs ou build iOS n’est compté comme réussi.

- Build Android debug de l’étape 6 réussi (60 s). Une dernière vérification ciblée ajoute un contrôle de génération après les écritures SQLite et lectures de fichiers, juste avant les requêtes : le changement de compte pendant cette attente conserve le brouillon et bloque l’envoi. Test dédié réussi ; nouvelle analyse Dart sans erreur.

### Étape 7 — Contrats et nettoyage

- Registre exhaustif des 44 endpoints : requêtes Zod partagées avec les contrôleurs, réponses/pagination/erreurs explicites, transferts binaires et unions commandes/résultats/snapshots. Les valeurs monétaires, curseurs et soldes restent des chaînes exactes ; les données libres se limitent aux métadonnées historiques extensibles.
- Génération déterministe de 178 schémas et 44 méthodes Dart. Les DTO immuables préservent l’absence d’un champ et sa valeur explicitement nulle. Les commandes déjà en file utilisent un transport brut contrôlé qui conserve leur enveloppe d’origine ; test de deux envois identiques sans ajout de valeurs par défaut.
- Repositories dédiés pour identité, catalogue, équipe, ventes, récompenses, rapports et notifications ; les écrans n’appellent plus le transport HTTP générique. Les commandes en ligne et leur reprise durable quittent le view model ; reporting extrait du contrôleur. Les repositories capturent le compte/génération avant les attentes locales.
- Correction du résultat d’expédition : version de livraison distincte de la version de commande. Les versions affectées incluent commandes, livraisons et demandes de récompense. Les anciens résultats acceptés restent conservés.
- Test réel de chaque endpoint avec PostgreSQL restreint, AJV et décodage/réencodage des réponses par les DTO Dart. Validation des réponses binaires/plages séparée. La CI exécute cette vérification et refuse toute dérive du contrat ou des fichiers générés.
- Installation reproductible vérifiée par `npm ci`, génération Prisma et `flutter pub get --enforce-lockfile`. NestJS 12.0.4/Swagger 12.0.1, Firebase Admin 14.4.0, Nodemailer 10.0.10 ; Prisma reste en stable 7.10.0 avec deux overrides ciblés de dépendances CLI. `npm audit` : aucune vulnérabilité connue rapportée lors de cette passe.
- Vérifications : compilation TypeScript, 6 tests domaine, 20 PostgreSQL, 3 traitements média réels, 44 endpoints HTTP et 1 test Dart de leurs réponses ; 48 tests Flutter dans la passe complète et un cas de transport supplémentaire ensuite (4 tests ciblés réussis). Les 2 parcours de synchronisation HTTP/SQLite/PostgreSQL passent. Analyse Dart sans erreur, `git diff --check` sans erreur. Les 3 tests qui exigent un serveur sont ignorés dans la passe Flutter standard et exécutés par leurs scripts dédiés.
- Limites : cette couverture HTTP n’est pas la recette des trois parcours UI prévue à l’étape 9. La CI distante et le build iOS attendent un dépôt distant/macOS. Aucun résultat de charge, de push réel ou d’appareil physique n’est revendiqué.
