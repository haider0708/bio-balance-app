# État de l’implémentation — 23 septembre 2026

La [correction de synchronisation 1.1.4+8](sync-recovery-2026-09-23.md) traite les opérations de tous les magasins depuis chaque espace, avec état en direct et magasin indiqué. Les paramètres retirent les sélecteurs redondants tout en conservant les réglages. Analyse sans diagnostic, 252 tests Flutter réussis, deux parcours HTTP réels et reprise après arrêt Android forcé réussis. Les identifiants et données sont conservés ; backend et schéma inchangés. APK/AAB signés depuis `ef99ad3`, candidate installée sur Samsung sans effacement, session conservée et file vérifiée vide. Réception rejetée conservée dans l’historique des résolutions. Voir la preuve de livraison pour la CI et les contrôles physiques.

La [refonte du graphique 1.1.3+7](chart-refinement-2026-09-23.md) ajoute les mesures montant/unités/ventes, une bulle de valeur, une moyenne quotidienne et une vue agrandie. Les liens de ventes gardent le magasin d’origine. Aucun changement backend ni migration. Analyse sans diagnostic et 239 tests Flutter réussis ; quatre scénarios à fixtures ignorés par la commande générique. APK/AAB signés depuis `cd867b2`, version installée sur Samsung avec session et données conservées. Démarrage et présence des commandes vérifiés ; parcours tactile complet sur appareil non revendiqué. Voir les preuves liées pour le statut CI ; les résultats précédents ci-dessous restent historiques.

Les [améliorations du graphique et des paramètres](chart-settings-2026-09-23.md) sont implémentées pour Android 1.1.2+6 : points interactifs, détail exact par jour, ouverture des ventes et accès unifié aux réglages magasin/groupe/administration. Validation locale : analyse sans diagnostic, 231 tests Flutter réussis, parcours des trois rôles et reprise après arrêt forcé sur Android réussis. APK/AAB signés depuis `95ceaa6` ; la candidate est installée sur le Samsung, sans effacement, avec session conservée et interaction du graphique/menu vérifiée. Aucun changement backend ni migration. La CI `35881790786` du code 1.1.2 a terminé avec succès : backend, Android, parcours Android et iOS non signé.

Les [corrections après essai Samsung](phone-feedback-2026-09-23.md) précédentes restent déployées : backend `a9fd576`, APK Android 1.1.1+5 installé sans effacement des données. Leurs 105 tests backend, contrats HTTP et preuves de déploiement/restauration restent historiques. La CI `35875356803` a réussi backend, Android et iOS non signé ; son test de reprise a échoué sur un ancien libellé de lot. Ce sélecteur est corrigé et le scénario a réussi localement dans la présente mise à jour.

Le [registre de refonte](redesign-2026-09-23.md) conserve le détail des migrations, tableaux de bord et essais de charge. Les seuils du pic de charge, la qualification physique complète et le pilote restent ouverts. Les entrées du 22 septembre ci-dessous sont historiques.

# Historique — 22 septembre 2026

Les corrections de la dernière passe d’audit sont implémentées, vérifiées localement et en CI. Une candidate Android 1.0.1+3 est signée et sa mise à jour depuis 1.0.0+2 est vérifiée sur émulateur ; l’application n’est pas encore qualifiée sur appareils physiques et en pilote. Ce document distingue les fonctionnalités codées des vérifications réalisées.

Dernière passe : [revue, fiabilité et finition](review-polish-2026-09-22.md). Le [registre VPS](vps-readiness-2026-09-22.md) établit le déploiement, la charge et la restauration actuels. Les comptes de tests et états des étapes antérieures ci-dessous sont historiques.

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
- Annonces du responsable, notifications opérationnelles, boîte interne hébergée sur le VPS ; Firebase retiré, alertes OS app fermée reportées.
- Vue administrateur, historiques paginés de ventes/points/audit/mouvements et export des lignes affichées.
- Docker Compose VPS, deux API, workers séparés, Nginx, migrations, sauvegarde locale, restauration isolée, CI et scénario k6.

## Vérifications actuelles

| Vérification | Résultat constaté |
|---|---|
| Compilation TypeScript | Réussie |
| Tests domaine et harnais backend | 19 réussis |
| Tests PostgreSQL réels et services | 26 transactions + 14 régressions d’audit + 4 médias + 5 notifications/workers + 13 sécurité + 11 email réussis |
| Tests Flutter de reprise, migration et dispositions d’écran | 146 réussis ; 4 tests à fixtures omis par défaut. Contrats et 2 parcours HTTP relancés séparément ; preuve HTTPS/Nginx antérieure conservée |
| Builds et parcours natifs | APK/AAB 1.0.1+3 signés, sécurité du manifeste et alignement natif vérifiés ; parcours/force-stop/vidéo réussis ; mise à jour APK 1.0.0+2 → 1.0.1+3 réussie sur émulateur ; compilation iOS CI réussie, signature Apple et appareils physiques en attente |
| Sauvegarde/restauration isolée | Réussie : données métier, image et vidéo traitées ; tailles/empreintes et projections comparées après restauration isolée |
| OpenAPI et génération Dart | 45 endpoints vérifiés sur HTTP réel ; schémas Dart typés générés et aller-retour JSON validé |
| Images Docker et émulateur | Parcours Android et Compose complet local réussis ; API/média, TLS, isolation, reprise et rollback vérifiés |

Un passage des tests PostgreSQL a expiré pendant une forte saturation mémoire de l’hôte par les builds Android. Après arrêt des anciens daemons de compilation devenus inutiles, les 12 tests ont réussi sans allonger leur délai.

Audit précédent : [constats et preuves](audit-2026-09-22.md). La [dernière passe](review-polish-2026-09-22.md) fournit les commits, CI, empreintes et candidate Android qui remplacent les anciens artefacts de compilation. Les entrées détaillées ci-dessous conservent l’historique des étapes.

## Travail restant avant acceptation

- Essais physiques Android 4 Go et iOS : caméra, accessibilité, mémoire, démarrage, fluidité et transferts interrompus.
- Compte Apple, signature iOS/TestFlight, inscription Google Play et validation des mises à jour Play/APK avec la même clé.
- Validation des données commerciales réelles ; les stocks, lots, comptes et sept prix de démonstration doivent rester identifiés comme tels jusqu’à leur remplacement.
- Pilote de cinq magasins pendant au moins deux semaines, correction et nouvelle vérification des retours.
- SPF/DKIM/DMARC passent et les messages arrivent ; leur classement Gmail doit encore être suivi avec de vrais envois consentis.

Le VPS, HTTPS, SMTP, sauvegarde/restauration et qualification 100/200 req/s disposent de preuves dans le registre VPS. Les notifications OS application fermée, les sauvegardes hors VPS, la haute disponibilité, les abonnements payants, l’admin web, WhatsApp et les classements hors magasin restent reportés selon le périmètre approuvé.

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
| 8. Notifications/workers | Boîte interne VPS et workers vérifiés ; Firebase retiré et notifications OS app fermée reportées |
| 9. Parcours complets | Vérification locale terminée sur émulateur Android ; iOS/appareils physiques en attente |
| 10. Performances/appareils | Charge VPS 100/200 req/s et SQLite vérifiées ; qualification sur appareils physiques en attente |
| 11. Déploiement/reprise | Compose, VPS/HTTPS, CI, sauvegarde/restauration et rollback vérifiés ; aucun rétablissement hors serveur prévu |
| 12. Versions signées/pilote | Candidate Android 1.0.1+3 signée et mise à jour privée testée ; Apple, Play et pilote de deux semaines en attente |

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

Étape 3 : commit fonctionnel `a57026b`, correction de l’assertion de régression `9dd2eb6`. La passe complète a relevé une attente obsolète dans le nouveau test d’éditeur (elle demandait à tort un brouillon vide). L’assertion vérifie maintenant la conservation du lot saisi et l’absence de stock ajouté avant confirmation de vente. La suite complète réussit : 29 tests Flutter ; les 2 parcours HTTP réels sont exécutés séparément et réussissent.


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

Commit : `43b75ef`. Régénération après commit sans différence vérifiée.

- Registre exhaustif des 44 endpoints : requêtes Zod partagées avec les contrôleurs, réponses/pagination/erreurs explicites, transferts binaires et unions commandes/résultats/snapshots. Les valeurs monétaires, curseurs et soldes restent des chaînes exactes ; les données libres se limitent aux métadonnées historiques extensibles.
- Génération déterministe de 178 schémas et 44 méthodes Dart. Les DTO immuables préservent l’absence d’un champ et sa valeur explicitement nulle. Les commandes déjà en file utilisent un transport brut contrôlé qui conserve leur enveloppe d’origine ; test de deux envois identiques sans ajout de valeurs par défaut.
- Repositories dédiés pour identité, catalogue, équipe, ventes, récompenses, rapports et notifications ; les écrans n’appellent plus le transport HTTP générique. Les commandes en ligne et leur reprise durable quittent le view model ; reporting extrait du contrôleur. Les repositories capturent le compte/génération avant les attentes locales.
- Correction du résultat d’expédition : version de livraison distincte de la version de commande. Les versions affectées incluent commandes, livraisons et demandes de récompense. Les anciens résultats acceptés restent conservés.
- Test réel de chaque endpoint avec PostgreSQL restreint, AJV et décodage/réencodage des réponses par les DTO Dart. Validation des réponses binaires/plages séparée. La CI exécute cette vérification et refuse toute dérive du contrat ou des fichiers générés.
- Installation reproductible vérifiée par `npm ci`, génération Prisma et `flutter pub get --enforce-lockfile`. NestJS 12.0.4/Swagger 12.0.1, Firebase Admin 14.4.0, Nodemailer 10.0.10 ; Prisma reste en stable 7.10.0 avec deux overrides ciblés de dépendances CLI. `npm audit` : aucune vulnérabilité connue rapportée lors de cette passe.
- Vérifications : compilation TypeScript, 6 tests domaine, 20 PostgreSQL, 3 traitements média réels, 44 endpoints HTTP et 1 test Dart de leurs réponses ; 48 tests Flutter dans la passe complète et un cas de transport supplémentaire ensuite (4 tests ciblés réussis). Les 2 parcours de synchronisation HTTP/SQLite/PostgreSQL passent. Analyse Dart sans erreur, `git diff --check` sans erreur. Les 3 tests qui exigent un serveur sont ignorés dans la passe Flutter standard et exécutés par leurs scripts dédiés.
- Limites : cette couverture HTTP n’est pas la recette des trois parcours UI prévue à l’étape 9. La CI distante et le build iOS attendent un dépôt distant/macOS. Aucun résultat de charge, de push réel ou d’appareil physique n’est revendiqué.

### Étape 8 — Notifications et workers

Commit : `bdb14a7`.

- Migration additive `202609210009_notification_jobs`, appliquée en développement et test : nature/audience des notifications (annonces anciennes réconciliées), propriété du bail des jobs, reçus d’envoi par notification/appareil/session.
- Messages opérationnels réservés aux responsables/propriétaires/admin actifs. Les annonces restent des envois volontaires du responsable. La boîte de réception, la lecture individuelle et le worker revérifient les permissions actuelles ; une rétrogradation ou révocation rend les messages concernés inaccessibles.
- Recontrôle des sessions avant envoi, reprise des seuls appareils en échec, suppression des tokens invalides. Une ancienne inscription ne peut pas reprendre le token d’une session plus récente ; le désenregistrement est limité à sa session. Le message OS est volontairement générique : son contenu métier est relu par l’API autorisée.
- Flutter : renouvellement des tokens, permission refusée, sérialisation suppression/inscription pour les changements de compte, callbacks liés à la génération, déduplication bornée des messages/taps. Réception au premier plan et ouverture depuis une notification : sauvegarde des brouillons, sélection du magasin autorisé, affichage du message ; accès retiré et réponse tardive restent bloqués.
- Correction des refus HTTP : une action interdite (`FORBIDDEN`) ne révoque plus à tort tout le magasin ; les erreurs d’accès d’un transfert binaire sont décodées avant reprise de session.
- Worker extrait en composant testable : claim exclusif, bail renouvelé, refus des terminaisons d’un ancien propriétaire, huit tentatives, délai avec aléa/plafond et diagnostics sans secrets. Parallélisme borné (2 par défaut, 4 maximum), média limité à 1 et type de tâche isolé. Les contrôles horaires paginent les magasins et utilisent une identité stable ; leur reprise ne duplique ni audit ni alerte.
- Validation locale : 5 tests PostgreSQL dédiés aux audiences, révocations, expirations, transfert de token, reprise partielle, claims concurrents, bail périmé, échecs et contrôles horaires. 53 tests Flutter dans la suite complète ; 4 tests push ciblés repassés après suppression de l’ancien token. Les 20 tests transactionnels et 6 tests domaine restent passants. 45 contrats HTTP et leur aller-retour Dart validés. Analyse Dart sans erreur ; APK debug compilé.
- Limites : les passerelles FCM/APNs sont simulées dans les tests locaux. L’acheminement réel sur Android/iOS et les permissions natives exigent la configuration plateforme/appareils. Les services externes sont au moins une fois : une réponse FCM/SMTP perdue peut occasionner une répétition ; identités stables, reçus, collapse IDs et déduplication mobile réduisent ce risque sans promettre une livraison exactement une fois. Un message OS déjà en file peut arriver après déconnexion, sans contenu métier.


### Étape 9 — Parcours complets et pannes

Commit : `a8b4610`.

Implémentation et validation locale terminées ; validations iOS et physiques en attente.

- Parcours Flutter natif administrateur → responsable → vendeur contre Nest/HTTP et une base PostgreSQL isolée avec rôle restreint. Activation réelle, MFA admin, magasin, produit/formation, stock initial, prix/points, équipe, récompense, commande/expédition/réception, vente/correction/retour, demande/remise de récompense, annonce/boîte de réception et accès retiré pendant une saisie.
- Parcours des trois rôles réussi sur émulateur Android API 36 : trois révisions, attribution d’origine conservée, livraison reçue, récompense produit remise, stock final 21, solde vendeur 20 et réservation 0. Ce résultat ne constitue pas un essai iOS ni physique.
- Correction d’une course réelle de navigation : une sauvegarde terminée pendant l’animation Retour ne peut plus fermer l’écran précédent. Régression dédiée réussie ; confirmation asynchrone appliquée aux ventes, réceptions, commandes, formulaires, onboarding et publications.
- Carte de demande de récompense identifiant désormais le membre demandeur. Cycle de vie caméra et erreurs natives gardent la saisie manuelle accessible.
- 69 tests Flutter réussis : panne SQLite réelle par limite de pages, rollback atomique, conservation des brouillons/anciennes opérations, 14 dispositions sur sept écrans (portrait/paysage, clavier, texte 200 %, labels accessibles), reprise des transferts et sessions. Trois tests nécessitant un serveur restent exécutés séparément : 45 contrats HTTP/DTO et deux parcours de synchronisation réussis.
- 6 tests métier, 20 tests PostgreSQL, 3 tests médias et 5 tests notifications/workers repassés. Analyse Dart sans erreur ; installation Flutter avec lockfile imposé réussie.
- Harnais Android force-stop : conserve l’installation entre phases, vérifie le PID avant/après arrêt, contrôle les octets de l’outbox avant relancement. Vérification native réussie : une seule acceptation serveur, stock 7/version 3/points 30 ; permission caméra refusée avec recherche manuelle utilisable ; vidéo H.264 lue en ligne, téléchargée avec vérification, puis lue hors ligne depuis un fichier local. Les codes de sortie du premier driver ne servent pas de preuve : Flutter peut retourner zéro après perte de connexion.
- Job CI Android émulateur ajouté ; variante du parcours de rôles préparée pour simulateur iOS. Dépôt distant/macOS, appareils physiques, caméra réelle, screen reader manuel et acheminement FCM/APNs restent en attente. Les journaux locaux sont conservés dans `.artifacts/evidence/step9/` (ignorés par Git) ; procédures dans `tests/journeys/README.md`.

Résolu à l’étape 11 : variables et fichiers secrets explicitement limités par service ; les API/workers ne reçoivent plus les credentials du propriétaire/migrations.

### Étape 10 — Charge et mesures

Implémentation et mesures locales terminées ; qualification VPS et appareils physiques en attente. Commit : `dfeeacd`.

- Générateur reproductible pour 125 organisations, 500 magasins, 5 000 comptes, 200 produits, 300 000 lots et deux millions de ventes avec révisions, mouvements, points, audits et curseurs. Refus d’une base peuplée, aucune suppression d’historique ; comptes de test et tokens privés séparés des preuves versionnées.
- k6 2.3.0 vérifié par checksum ; deux API en mode production, curseurs persistants par compte/magasin, pagination des snapshots et mélange de lectures/ventes. Workflow de charge manuel préparé ; CI distante non exécutée.
- Les premiers pics échouaient par saturation CPU. Profils conservés ; accès courant regroupé dans la transaction, projections paginées typées, petites collections de snapshot groupées, lectures vides supprimées et alertes lues par groupe de produits. Aucun cache de droits, aucune réduction des données autorisées. Soldes >2^53 vérifiés exactement.
- Reprise bornée des conflits de sérialisation/deadlock exposés directement au commit par l’adaptateur PostgreSQL ; quatre tests dédiés vérifient tentatives, épuisement et non-reprise des autres erreurs. Deux nouveaux tests PostgreSQL couvrent droits/sessions courants, pagination sans doublon, portée vendeur, filtres produit et soldes exacts.
- Mesure finale sur i5-1135G7/16 Go : 100 req/s pendant 5 min + 200 req/s pendant 30 s. 36 001 requêtes, 3 603 ventes acceptées, zéro erreur/rejet/itération perdue. p95 lecture/écriture : 20,91/49,28 ms en continu ; 164,78/367,87 ms au pic. Vérification finale : aucun stock/version/solde/révision incohérent sur 2 015 587 ventes conservées.
- Benchmark Flutter VM Linux : 120 enregistrements durables p95 15,580 ms ; recherche 0,184 ms ; changement de magasin 11,505 ms ; réouverture SQLite 15,481 ms. Ces chiffres ne mesurent pas le démarrage ou le rendu natif.
- Validation : compilation TypeScript, 10 tests métier/reprise, 22 PostgreSQL, 5 notifications/workers, 45 contrats HTTP et les deux parcours de synchronisation HTTP/SQLite/PostgreSQL passants. Dérive du contrat/fichiers générés absente, analyse Dart sans erreur et syntaxe des scripts vérifiée.
- Preuves versionnées et conditions : `docs/performance-evidence.md`, `tests/performance/evidence/`. Procédure physique : `tests/performance/devices.md`. Le test local exclut Nginx/TLS/workers : la capacité du VPS complet, le démarrage ≤2,5 s, les images manquées <1 %, caméra/vidéo/mémoire et iOS physiques restent des portes de sortie non validées.


### Étape 11 — Déploiement et reprise

Implémentation et vérification locale terminées ; CI distante, VPS et ACME réel en attente. Commit : `8e71caf`.

- Harnais reproductible `tests/deployment/run.sh` : projet Compose isolé, données conservées, HTTPS local, deux API, workers séparés, PostgreSQL privé et Mailpit. Neuf migrations, rôle restreint, bootstrap administrateur et MFA réels.
- Défaut de packaging corrigé : dépendances npm du workspace copiées dans les images ; smoke check des modules Nest/Firebase/SMTP pendant le build. Environnements limités par service, accès média contrôlé, processus applicatifs non-root/read-only, rotation des logs et arrêts gracieux.
- Nginx résout les nouvelles adresses des API après remplacement. Reprise vidéo Flutter corrigée pour utiliser l’ETag opaque réellement fourni par Nginx ; le SHA-256 final reste la preuve d’intégrité. Test HTTPS réel : interruption, réouverture SQLite, réponse 206 et fichier complet vérifié.
- Reprise d’un bail expiré après redémarrage, diagnostic d’un job en échec puis reprise contrôlée avec son identité originale. Invitation SMTP envoyée uniquement à Mailpit ; isolation des variables/credentials, absence de port PostgreSQL public et RLS sans contexte vérifiés.
- Exercice complet réussi : rollback vers le code `a8b4610` (packaging corrigé, schéma compatible) puis retour aux images actuelles. Respectivement 287 et 286 lectures autorisées pendant les remplacements, aucune incohérence ; relecture de la vente acceptée sans nouvel effet. Stock final 4/version 3/points 60.
- Sauvegarde/restauration isolée : une vente/révision, deux mouvements, projections et deux médias traités (PNG et H.264) identiques ; taille et SHA-256 de chaque fichier contrôlés. Les volumes, sauvegardes et bases restaurées restent disponibles localement.
- Bootstrap/renouvellement TLS, installation avec validation clé/certificat et rechargement préparés ; certificat incompatible refusé et remplacement local réussi. Timers sauvegarde/supervision/TLS validés par systemd-analyze avec chemins locaux ; ils ne sont pas installés sur un VPS. Supervision vérifie ressources, fraîcheur des sauvegardes, services et jobs.
- Vérifications : images API/média et rollback compilées, harnais complet réussi, 70 tests Flutter (4 cas serveur ignorés dans la suite standard), 5 tests de téléchargement ciblés, reprise HTTPS réelle exécutée séparément ; analyse Dart sans erreur. Preuves résumées dans `tests/deployment/evidence.json`, journaux privés dans `.artifacts/evidence/step11/`.
- Limites : certificat local auto-signé, SMTP Mailpit et fichier FCM factice. ACME/DNS, SSH/firewall, alertes externes, FCM/APNs, CI distante et macOS/iOS attendent leurs environnements. Une restauration locale ne couvre pas la perte totale du VPS ; haute disponibilité et sauvegarde hors serveur restent reportées.


### Étape 12 — Artefacts et préparation du pilote

Préparation locale terminée ; les versions signées et l’acceptation pilote restent en attente. Commit : `7f7bf4e`.

- Script de construction avec configuration HTTPS par environnement/plateforme, refus des valeurs de test pour une version signée, clés Android existantes exigées ; préparation de l’équipe Apple, export IPA et entitlements APNs debug/release. Les fichiers locaux de configuration/signature restent ignorés.
- Android 0.1.0+1 (`tn.biobalance.app`, min SDK 24, cible 36) : APK release 84,4 Mo et AAB 76,7 Mo compilés et vérifiés **sans signature**, URL réservée `.invalid`, aucune configuration Firebase réelle. Alignement ZIP et segments ELF 64 bits ≥16 Kio validés. Ce sont des preuves de compilation, pas des fichiers de pilote installables.
- APK debug de l’entrée normale `lib/main.dart` installé/lancé sur émulateur ; cache du compte synthétique conservé, rechargement à chaud réussi. Aucun effacement de SQLite/outbox pour revenir de l’application de test à l’application normale.
- La dernière recette a trouvé puis corrigé un message caméra qui recouvrait le bouton de recherche manuelle. Erreur désormais dans l’écran, gestion du cycle de vie unique et démarrage concurrent évité ; portrait/paysage à texte 200 % vérifiés. Les harnais attendent la fermeture réelle du clavier et leur nettoyage ne peut plus arrêter le processus de la phase suivante.
- Validation finale : 72 tests Flutter réussis, 4 cas avec serveur exécutés séparément aux étapes précédentes ; 7 tests de configuration/packaging ; analyse Dart sans erreur. Parcours complet des trois rôles repassé sur Android (stock 21, points 20, trois révisions). Force-stop/reprise repassé (mêmes octets/ID, une acceptation, stock 7/v3, points 30), caméra refusée avec saisie manuelle et vidéo H.264 téléchargée/lue hors ligne réussies. Les échecs intermédiaires restent dans les journaux.
- Dossier de livraison préparé : contrat, migrations, code du commit, design dans les sources Flutter, notes de version, documentation d’exploitation/restauration, preuves résumées et sommes SHA-256. Le packager refuse fichiers supplémentaires, empreintes modifiées et points d’entrée de test ; il ne copie ni credentials, ni données, ni sauvegardes privées.
- Spécification/architecture mises à jour et plan de pilote de cinq magasins pendant au moins quatorze jours, recette des trois rôles/deux plateformes et registre d’incidents ajoutés. Aucune invitation réelle, publication Play/TestFlight ou période de pilote n’a été effectuée.
- Restent externes : dépôt/CI macOS, VPS/domaine/ACME, SMTP réel, Firebase/APNs, clés/comptes de signature, appareils physiques et participants du pilote. Les objectifs physiques et la charge du VPS complet doivent être démontrés avant acceptation. Haute disponibilité et récupération après perte totale du VPS restent hors périmètre.

Le registre ne déclare pas la production prête : `release-gates.md` distingue les passes locales des portes externes encore ouvertes. Preuves finales : `tests/release/evidence.json` et `.artifacts/evidence/step12/`.

## Audit de sécurité, logique et qualité — 22 septembre 2026

Commit de correction : `2ccfbc5778eacfd45269f6eec0cdce45f4ca23ec`. Configuration des associations de domaine et clôture du registre dans le commit de documentation suivant. Le [rapport de corrections](audit-2026-09-22.md) et le [résumé des preuves](../tests/audit/evidence-2026-09-22.json) complètent les douze étapes.

- Revue du backend, mobile, contrats, migrations, médias, workers et exploitation, avec lectures spécialisées et contrôle indépendant. Neuf constats de sécurité validés sur le point de départ sont corrigés : course connexion/récupération, calculs Argon2 non bornés, droits globaux périmés, capacité média, diffusion push, persistance des refus de session, liens de récupération privés, lecture binaire avant authentification et rétention des compteurs.
- Accès et transactions globales centralisés ; catalogue concurrent protégé ; invitations compatibles avec les reprises ; curseurs validés. Pagination cohérente de toutes les opérations non terminées et allocation des cadeaux au-delà de mille lots. Outbox/v1 et historiques conservés. Durcissement CSV/DTO, TypeScript strict sur les éléments inutilisés et formatage backend contrôlé en CI.
- Deux migrations additives appliquées et vérifiées dans les bases isolées. Réservations de capacité, reçus SHA-256 de fragments, nettoyage des temporaires et contrôles de sauvegarde. Aucun historique métier réécrit, aucune opération locale supprimée.
- Les parcours natifs ont trouvé un crash du lecteur lors du passage de la vidéo distante à son fichier local. État du contrôleur et disponibilité modifiés atomiquement ; regression avec destruction native retardée. Le parcours force-stop/synchronisation/caméra refusée/vidéo hors ligne repasse ensuite avec stock 7, version 3 et points 30.
- Vérifications finales : 55 tests backend (10 domaine/reprises, 22 PostgreSQL, 14 audit, 4 média, 5 notifications), 45 endpoints HTTP et leur décodage Dart, 79 tests Flutter plus les 4 cas serveur séparés, 9 tests Python, parcours natifs des trois rôles et arrêt/reprise Android. TypeScript, analyse Flutter, installation lockfiles et APK debug normal réussis. Régénération du contrat après commit sans différence : 183 schémas, 45 endpoints. Audit npm sans vulnérabilité connue rapportée.
- Charge locale : 500 magasins, 5 000 comptes, 300 000 lots, plus de deux millions de ventes. 36 001 requêtes, zéro erreur/rejet/itération perdue, intégrité stock/points/révisions/identités vérifiée. Au burst de 200 req/s, p95 lecture 104,87 ms et écriture 214,55 ms. La première passe échouée a conduit à réduire les allers-retours SQL ; son résultat reste conservé.
- Compose complet, 11 migrations, TLS local, droits restreints, plages média, workers, backup et restauration avec PNG/H.264 réussis. Rollback de laboratoire vers `6e8ec3b`, puis retour au code corrigé : 275/289 lectures autorisées sans divergence. Le harnais respecte désormais les compteurs MFA entre probes successifs. Conteneurs et émulateur de cette recette arrêtés, données et preuves conservées.
- Scan Codex Security finalisé et indexé sous `405b4f79-2fd3-4e69-ba93-7608b88b1a00` ; les constats du rapport concernent le commit initial. Les correctifs, résultats et échecs intermédiaires sont reliés dans le dossier d’audit. Les bibliothèques/binaires tiers ne sont pas présentés comme du code relu manuellement.

Limites restantes : CI distante/macOS/iOS, appareils physiques, associations de domaine, VPS/ACME/supervision réels, SMTP/push réels, signatures et pilote. Les anciens APK/AAB release doivent être reconstruits avec les correctifs avant le pilote. Aucun objectif physique ni capacité du VPS complet n’est déclaré validé par ces tests locaux. Sauvegardes hors serveur et haute disponibilité restent reportées.

## Renforcement de sécurité — distribution Play et APK privés

Décision utilisateur du 22 septembre : aucun Firebase. La boîte interne demeure hébergée sur le VPS ; les notifications OS app fermée sont reportées. Les mentions FCM/APNs dans les étapes historiques décrivent l’ancien choix et ne constituent plus des prérequis de cette version. Voir [sécurité et signatures](security-hardening.md).

- Deux clés Android RSA-4096 créées hors dépôt (application/upload), empreintes publiques versionnées et vérification avant/après build. Obfuscation Flutter, R8, symboles privés et contrôle des sections DWARF natives. L’installation et la mise à jour avec la bonne clé réussissent ; Android refuse la mauvaise clé sur l’émulateur isolé API 36.
- HTTPS requis en release, cleartext interdit, requêtes authentifiées limitées à l’origine API et redirections refusées. Écran Android sécurisé et couverture du sélecteur d’apps iOS ; validation iOS native encore externe.
- Budgets PostgreSQL atomiques partagés entre sessions et réplicas, coûts des lots de synchronisation, plafonds d’exports/snapshots, réponses 429 avec `Retry-After`, nettoyage borné. La déconnexion reste disponible après épuisement d’un budget. Migration 12 additive, sans modification des historiques/outbox.
- Limites Nginx, TLS 1.2/1.3, corps JSON compressés refusés, timeouts HTTP bornés, `no-store`. SDK/configuration Firebase retirés des clients, API et workers ; aucun job push neuf, jobs historiques consommés sans inventer de livraison. L’écran compte présente la boîte interne au lieu d’un bouton d’activation indisponible.
- Vérifications locales : 62 tests backend au total, 83 tests Flutter, 45 contrats HTTP et aller-retour Dart, 2 parcours HTTP/SQLite/PostgreSQL, 14 tests Python de release/backup/signature. TLS et CA non fiables refusés, 429 JSON testés, isolement et médias/ranges vérifiés sur les vrais conteneurs. Les artefacts de signature ciblent `.invalid` et ne sont pas des builds de pilote.
- Restent : sauvegarde chiffrée des clés, inscription Play et essais entre canaux réels, domaine/TLS/VPS réel, macOS/équipe Apple, essais physiques et pilote. Attestation Play Integrity/App Attest et pinning non actifs ; ces protections exigent leur configuration et une validation compatible avec les APK privés et la reprise hors ligne.

Les preuves détaillées de cette passe sont conservées sous `.artifacts/evidence/security-hardening/` et résumées dans `tests/security/evidence.json`. Le rapport d’audit précédent reste immuable ; ce renforcement ne réécrit pas ses constats historiques.

Charge après renforcement : 36 001 requêtes, 3 602 ventes acceptées, aucune requête échouée/opération rejetée/itération perdue. p95 lecture/écriture à 100 req/s : 26,11/46,69 ms ; à 200 req/s : 124,47/232,06 ms. Deux API locales sans Nginx/workers ni quotas CPU Compose dans cette mesure ; ne pas présenter ces chiffres comme une qualification du VPS. Le contrôle d’expiration concurrente des compteurs de maintenance a été ajouté ensuite sans modification du chemin HTTP mesuré.

Commit du renforcement : `c341080`. Contrats régénérés après commit : aucune dérive. Les clés privées restent hors du dépôt ; seules leurs empreintes publiques sont versionnées.
Reprise Flutter de média HTTPS/Nginx rejouée après le commit : réussie, avec autorité de test explicite, interruption, ETag et requêtes Range. Laboratoire et émulateur de sécurité arrêtés ; données et preuves conservées.

## Scanner et consommation mobile — 22 septembre 2026

Commit d’implémentation : **`873f641`**. Scanner à décodage limité, transitions caméra sérialisées et capture unique, cadre/torche/reprise ; index des codes et équivalence UPC/EAN validée. Stock/catalogue paresseux, préparation des grands inventaires dans un isolate borné, résumés réutilisés, images décodées à la taille affichée, polling suspendu hors écran/en arrière-plan et reprise avec délai après échec.

Validation : **96 tests Flutter réussis**, analyse propre, benchmarks SQLite et inventaire exécutés, APK/AAB release obfusqués non signés compilés et contrôlés. Quatre tests historiques dépendant d’un serveur ne sont pas comptés dans cette passe. Le calcul de filtrage sur 2 000 produits/6 000 lots passe de 16,413 à 0,531 ms p95 sur l’hôte ; la préparation initiale est déportée du thread UI. Caméra, batterie, mémoire et fluidité sur appareils physiques restent à vérifier. Voir [rapport détaillé](mobile-performance-2026-09-22.md) et [preuves](../tests/performance/evidence/mobile-resources-2026-09-22.json).

## Expérience mobile des trois rôles — 22 septembre 2026

Commit d’implémentation : **`92df40d`**. Interface et preuves détaillées dans [le rapport UX](mobile-ux-2026-09-22.md) et [le résumé des preuves](../tests/ux/evidence-2026-09-22.json).

- Accueils compacts, lignes de listes à la place des grandes cartes, petits aperçus d’images, texte courant 16 sp/secondaire 14 sp et cibles 48 dp. Navigation courte sur téléphone, menu défilant pour texte agrandi/paysage et rail sur écran large. Magasin visible, recherche dans le sélecteur et accès permanent au compte/synchronisation.
- Configuration depuis le téléphone regroupée dans Plus : coordonnées/images, équipe, guide, formations/annonces, récompenses et nouvelle page recherchable **Prix, points et seuils**. Le catalogue est recherchable. Les pages secondaires suivent les changements synchronisés ; les rôles limités à la réception ne voient plus les actions de vente/commande.
- Formulaires avec validation fixe au-dessus du clavier et des notifications ; choix recherchables, libellé restauré avec le brouillon, champs désactivés pendant l’envoi, double soumission évitée, conservation des valeurs après erreur et retour vers le premier champ incomplet. « Suivant » avance d’un seul champ. Les transactions, outbox, règles de points et historiques backend restent inchangés.
- La recette native a trouvé un bouton Enregistrer recouvert par une notification : pied déplacé dans le Scaffold et régression clavier + notification ajoutée. Fusion des manifestes debug/profile corrigée pour leurs accès HTTP locaux ; cleartext demeure refusé dans le manifeste de distribution. Les sélecteurs du harnais ciblent la feuille visible ; un tap manqué fait échouer le parcours.
- **115 tests Flutter réussis**, quatre cas dépendant d’un serveur exclus de cette suite, analyse Dart sans constat et formatage propre. Matrice des trois rôles à 360×800, 800×360 et 1024×768 en texte 100 %/200 %, mille choix recherchables, mises à jour catalogue/équipe et permissions de réception vérifiés. Captures Inter générées et examinées pour les trois accueils et les paramètres de produits.
- Parcours Android API 36 avec vraie API/PostgreSQL isolée réussi : activation, magasin/catalogue, réception, vente, correction, retour, cadeau, annonce et retrait d’accès depuis un éditeur. Vérifications finales : **stock 21, points 20, réservation 0, trois révisions**, livraison reçue et récompense remise. L’application normale `lib/main.dart` est ensuite recompilée/lancée ; hot reload réussi, aucune erreur runtime rapportée.
- Limites : émulateur en debug, aucune nouvelle mesure physique de cadence d’images/batterie/mémoire ou validation native iOS. Les essais sur téléphone Android de 4 Go, TalkBack/VoiceOver réels et pilote humain restent à réaliser. Les premiers échecs et les passes finales sont conservés sous `.artifacts/evidence/role-ux/`. Aucun déploiement ni nouveau build signé de distribution n’est déclaré par cette passe.

## Audit final — 22 septembre 2026

Commit applicatif : **`6ac660d51877d68afe3283ac7a5f927fd8187abc`**. Implémentation et régressions de cette passe : voir [rapport détaillé](final-audit-2026-09-22.md) et [preuves versionnées](../tests/audit/final-evidence-2026-09-22.json).

- Invitations et récupération revérifiées dans leur transaction, sessions iOS liées à l’appareil avec nouveau service Keychain, suppression bornée des pages expirées et codes d’emails en échec.
- Soumission durable distincte de l’actualisation de l’écran, protection contre les doubles enregistrements et écritures tardives, brouillons par lot/vente complétés avec l’outbox, restauration et erreurs de stockage récupérables. Aucun historique métier ni payload en attente réécrit.
- 68 tests backend et 130 Flutter réussis, analyse propre, 45 endpoints/contrats et deux parcours HTTP/SQLite/PostgreSQL validés, 14 tests Python. Parcours autonome Android des trois rôles réussi sur le code final ; application normale lancée puis hot reload sans erreur runtime.
- La reprise Android et la vidéo ont passé leurs assertions après réparation manuelle de l’état système de l’émulateur ; les deux essais précédents et cette limite sont décrits dans le rapport. iOS physique, VPS réel, CI distante et pilote restent non qualifiés.
- Migration additive `202609220004_snapshot_cleanup`. Les utilisateurs iOS existants doivent se reconnecter ; leurs opérations locales restent conservées.

- APK 79,7 Mo et AAB 71,9 Mo compilés depuis ce commit propre, entrée normale, obfuscation et contrôle ZIP/ELF 16 Kio réussis. Artefacts non signés, API `.invalid`, pas de distribution pilote. Le packager inclut les résumés versionnés d’audit/sécurité/UX ; 14 tests Python réussis après cette correction.
- Compose complet réussi avec 13 migrations, TLS local, accès restreints, médias protégés, vidéo interrompue/reprise et workers. Rollback compatible puis retour : 64 lectures autorisées par passage, stock 4/v3/points 60 conservés ; restauration des mêmes projections et de deux médias PNG/H.264 vérifiés par taille/SHA-256. Laboratoire arrêté, données conservées.
- Les premiers échecs de registre Docker et du harnais saturant le plafond de snapshots restent documentés. Le harnais utilise des lectures de lots bornées sans modifier les protections serveur. La clôture ajoute uniquement harnais/packaging et preuves ; aucun nouveau changement applicatif après le build.

Le VPS réel, les versions signées pour les canaux de distribution, les appareils physiques, CI/macOS/iOS et le pilote restent des conditions de diffusion ouvertes ; aucune case externe n’a été transformée en réussite locale.

## Installation sur go2code — 22 septembre 2026

Le backend est maintenant installé sur le VPS réel, accessible à **https://api.galylio.com**, derrière Cloudflare en mode Full (strict) confirmé. Le domaine `api.biobalance.com.tn`, encore absent du DNS public, a été remplacé à la demande de l’utilisateur.

- Apache existant conservé, Nginx privé sur loopback, deux API et deux workers, PostgreSQL privé et 13 migrations. Accès direct à l’origine refusé, adresses client vérifiées, droits applicatifs restreints.
- Compte administrateur avec MFA créé, configuration SMTP 465/TLS authentifiée, secrets conservés hors Git. Aucun email de test envoyé et aucune donnée métier factice créée.
- Recette HTTPS/MFA/révocation, médias PNG/H.264, répétition de transfert, empreintes et plages réussies. Sauvegarde avec les deux médias restaurée sur une base séparée ; backups nocturnes et contrôle de santé interne/public activés.
- Renouvellement Certbot simulé et hook Apache vérifié séparément. Correction des commandes Docker qui consommaient l’entrée du shell SSH lors d’une sauvegarde/restauration ; régression distante et 14 tests Python réussis. Les 19 tables RLS prévues par les migrations sont vérifiées ; l’autorisation des tables de répertoire reste assurée par les transactions serveur.
- Endpoint mobile local configuré ; builds signés pour ce domaine, CI/iOS, téléphones physiques et pilote restent à réaliser. Ressources adaptées au serveur partagé ; capacité à grande échelle et supervision indépendante encore à qualifier.

Compte rendu et résultats exacts : [déploiement VPS](vps-deployment-2026-09-22.md) et [preuves](../tests/deployment/vps-evidence-2026-09-22.json). Les anciennes étapes restent un historique de leurs environnements de test ; cette section consigne les vérifications réellement exécutées sur le VPS.

## Publication Android v1.0.0 — 22 septembre 2026

Code de construction : **`d09c552c07ad7997c5f493fdbbe74bf5261d8ce4`**, version **1.0.0+2**. Historique poussé sur `main` dans [le dépôt GitHub](https://github.com/haider0708/bio-balance-app). Les anciens APK de compilation utilisant `.invalid` ne sont pas les fichiers de cette release.

- APK universel signé avec la clé d’application existante, API compilée `https://api.galylio.com`, trois architectures vérifiées. AAB signé avec la clé d’upload conservé en privé pour l’inscription Play.
- Signature APK v2/RSA-4096, identité attendue, restrictions manifest, absence de sections DWARF natives et alignement 16 Kio vérifiés. Installation sur un émulateur Android 36 neuf et affichage de la connexion française réussis ; aucune erreur fatale BioBalance observée. L’essai d’installation trop tôt pendant le premier démarrage de l’émulateur a été repris après disponibilité du système.
- APK : 79 727 534 octets, SHA-256 `386f5b00c16dd82e3f030ca4b7c6b5335e4c45f80a4b2cafc7b2cc60c29bf21e`. Manifest et sommes de contrôle joints à la [release](https://github.com/haider0708/bio-balance-app/releases/tag/v1.0.0). Les clés, credentials, symboles privés et données locales sont exclus.
- GitHub Actions a démarré pour le commit de construction : backend, Android, parcours Android et compilation iOS non signée. Un job en cours ne vaut pas une validation ; consulter [l’exécution](https://github.com/haider0708/bio-balance-app/actions/runs/35738028697).
- Résultats distants déjà acquis : backend réussi et compilation iOS release non signée réussie sur macOS. Les jobs Android sont encore en cours au relevé de clôture ; leur résultat final reste à consulter. Le téléchargement public de l’APK renvoie HTTP 200 et les trois assets GitHub correspondent aux empreintes locales.

La publication de l’APK est distincte de l’acceptation générale : téléphones physiques, signature/distribution Apple, inscription Play, sauvegarde indépendante des clés, charge du VPS partagé, alertes externes, réception d’email et pilote restent à vérifier. Notes de version : [v1.0.0](releases/v1.0.0.md).

## Rétention automatique des sauvegardes — 22 septembre 2026

À la demande de l’utilisateur, les sauvegardes du VPS ne s’accumulent plus sans rotation. Jusqu’à 7 copies quotidiennes et 4 hebdomadaires sont conservées dans le budget de 4 Gio, copie en cours comprise, avec 10 Gio de réserve disque. Les copies les plus anciennes peuvent céder leur place, mais la dernière copie valide est toujours protégée. Une taille incompatible avec ces limites provoque un échec visible au lieu de remplir le serveur.

- Contrôle SHA-256, verrou de sauvegarde hérité par les producteurs, verrou partagé pendant la restauration, taille des flux bornée, publication atomique, nettoyage des fichiers partiels et limite systemd d’une heure. Les copies corrompues ou étrangères restent disponibles pour examen ; les liens symboliques sont refusés.
- 34 tests Python réussis. Le service réel a produit une nouvelle copie puis supprimé trois anciennes copies redondantes ; un second passage sur le code final a remplacé une autre copie ancienne. Deux ensembles valides restent présents, environ 248 Ko au total, sous le plafond prévu.
- Restauration isolée de la copie créée par le nouveau service : base et deux médias traités vérifiés. Seules les sorties temporaires de cette recette ont ensuite été supprimées. Les données de production sont conservées.
- Sauvegarde et moniteur terminent avec succès ; le timer nocturne reste actif. Journaux Docker déjà plafonnés à 5 × 10 Mo par service. Les erreurs de sauvegarde interrompue ou bloquée apparaissent dans la supervision locale ; acheminement externe et sauvegarde hors VPS restent reportés.

Preuves : [rétention VPS](../tests/deployment/backup-retention-evidence-2026-09-22.json). Paramètres et restauration : [runbook](runbook.md).

## Correction du parcours Android CI — 22 septembre 2026

Les trois premières exécutions GitHub ont terminé avec succès pour le backend, les builds Android et la compilation iOS non signée, mais ont échoué sur le parcours Android après la réception de stock. Le harnais attendait l’état inactif du workspace sous-jacent avant que l’écriture SQLite et la fermeture de la réception soient terminées. La navigation pouvait alors attendre un bouton Retour déjà disparu.

Le parcours attend désormais explicitement la fermeture de `ReceiptScreen` après la sauvegarde avant de naviguer. Le helper reconnaît aussi le rail de navigation des grandes fenêtres. Aucun délai arbitraire ajouté, aucune assertion métier retirée, aucun changement de stock de production. Analyse du fichier d’intégration réussie ; nouveau passage complet local/distant encore à confirmer. Un premier essai local a été interrompu après une ANR de System UI dans l’ancien émulateur ; il ne constitue pas une validation applicative.

## Emails d’accès et sécurité — 22 septembre 2026

Décision confirmée : les alertes métier restent dans l’application. Modèles HTML/texte centralisés pour invitation responsable/équipe, récupération et confirmation de changement de mot de passe. Rendu français minimal, contexte échappé, date d’expiration en heure de Tunis, codes manuels et liens HTTPS optionnels. Un test opérateur ne crée ni compte ni accès.

- Jobs versionnés, compatibilité en lecture des anciens jobs texte, autorisation d’invitation partagée entre activation et envoi, contrôle du compte/code avant chaque tentative, lease revérifiée avant SMTP, Message-ID stable et expurgation des codes après traitement.
- Confirmation de sécurité atomique avec changement du mot de passe/révocation des sessions ; récupération limitée aussi par destinataire. Les logs SMTP ne contiennent ni corps ni code.
- 11 tests email réussis, dont réception HTML/texte de trois messages dans Mailpit ; 22 tests d’intégration, 13 tests de sécurité, 14 d’audit, 5 de notifications et 10 de domaine/reprise DB réussis. Les 45 contrats HTTP et le décodage Dart réussissent.
- Parcours Android complet des trois rôles réussi avec le correctif de réception et les nouveaux jobs. L’essai local de reprise a été interrompu par la disparition du processus d’émulateur avant installation ; la CI distante doit encore confirmer l’ensemble. L’essai de contrats sans FFmpeg dans le PATH a été relancé avec l’outillage configuré et a réussi.
- Envoi réel vers l’adresse Gmail autorisée et installation VPS à consigner après exécution ; la réception dans la boîte Gmail ne sera pas déduite de l’acceptation SMTP.

Inventaire, aperçus, politique de reprise et ordre de déploiement : [emails](email-delivery.md).

Le passage CI `35744591825` confirme la résolution de l’attente après réception, mais révèle ensuite un toast temporaire devant « Se déconnecter ». Le helper attend maintenant une cible réellement touchable avant de cliquer, sans désactiver les erreurs de hit-test. Une régression widget reproduit l’obstruction puis vérifie le clic après disparition du snackbar ; elle réussit. Le résultat complet distant du correctif suivant reste à confirmer.

La reprise locale a aussi exercé un libellé non encore construit : le helper ne doit pas appliquer `.last` avant que le finder ait trouvé un résultat. Ce cas possède maintenant une seconde régression réussie. Le checkpoint de terminaison attend explicitement la fermeture de l’éditeur de vente après son commit SQLite, selon la même règle que la réception.

## Clôture CI et emails — 22 septembre 2026

Le commit **`c2ccab498ff29bdf0370f1b893c282879ae2af21`** passe les quatre jobs de [GitHub Actions 35746770350](https://github.com/haider0708/bio-balance-app/actions/runs/35746770350) : backend, Android, parcours Android et compilation iOS release non signée sur macOS. Les échecs intermédiaires ci-dessus restent l’historique de diagnostic ; leur statut en attente est remplacé par cette exécution complète réussie.

- 79 tests backend, 34 tests Python de release, 45 contrats HTTP/décodage Dart, analyse et vérifications Android réussissent dans ce pipeline. Les deux régressions de navigation ont aussi réussi localement.
- Parcours Android des trois rôles et arrêt réel du processus/reprise réussis en local et en CI. Compte, identifiant et payload de l’outbox conservés, une seule vente acceptée, stock **7**, version **3**, points **30** ; vidéo téléchargée lue hors ligne.
- Backend email **`caa50b4e828d4f4e92a79c99819f50ad4f575e3c`** installé sur le VPS après sauvegarde ; six services sains, HTTPS/MFA/déconnexion/moniteur réussis, aucun partenaire ou magasin factice créé. Les deux commits suivants concernent uniquement le harnais Android ; le code backend déployé est celui testé par la CI finale.
- Un email de diagnostic explicitement autorisé est accepté par le relais SMTP en une tentative ; job terminé et charge effacée. La recherche ciblée du Message-ID dans la boîte de l’expéditeur ne trouve aucun retour d’échec. **Réception et classement Gmail : confirmation du destinataire encore attendue.**
- Alertes métier conservées dans l’application. Les invitations responsable/équipe, récupération et confirmation de changement de mot de passe utilisent les modèles centralisés HTML/texte. L’APK signé v1.0.0+2 reste compatible ; aucun widget de production ni nouvelle version mobile n’a été nécessaire pour cette passe.

Preuves : [CI, déploiement et email](../tests/deployment/email-evidence-2026-09-22.json). Les mesures physiques, la distribution Apple/Play et le pilote conservent leurs conditions ouvertes dans [le registre de diffusion](release-gates.md). Cette clôture ne les compte pas comme réalisés.

## Simplification des emails — 22 septembre 2026

À la demande de l’utilisateur, les cinq modèles adoptent une colonne blanche de 480 px, une signature discrète, des titres/textes raccourcis et un code à bordure fine. Barres décoratives, grands aplats verts, pied répété et URL longue dupliquée retirés. Expiration directement sous le code, dates numériques en heure de Tunis et consignes de sécurité conservées. Aucun changement des autorisations, tokens, audiences, jobs ou migrations.

Compilation TypeScript, formatage et **11 tests email réussis**, dont l’envoi multipart vers Mailpit isolé. Aperçu mobile examiné avec code et expiration lisibles. Les exemples HTML/texte sont régénérés dans `.artifacts/email-previews/`. Révision **`2b3769bad8a78969c3eeb0a8c93ef427a72d241d`** installée sur le VPS après sauvegarde ; six services sains, Nginx validé/rechargé et HTTPS réussi. Le fichier de modèle du worker correspond au SHA-256 compilé localement. CI backend et iOS réussis ; jobs Android encore en cours au relevé dans [les preuves](../tests/deployment/email-refinement-evidence-2026-09-22.json). Aucun nouvel email externe envoyé pour cette retouche ; la précédente confirmation Gmail reste attendue.

## Catalogue, simulation et supervision — en cours le 22 septembre 2026

Import préparé à partir de `biobalance.tn` et des 39 codes EAN-13 du fichier fourni. Les deux références de déodorant éclaircissant restent séparées à la demande de l’utilisateur. Les champs absents ne reçoivent pas de prix zéro ou de code inventé. Images téléchargées pour l’import, décodées puis traitées par le pipeline applicatif ; description et source conservées dans le dossier opérateur privé.

Outils opérateur ajoutés : provisionnement borné de comptes démo avec mots de passe Argon2id, identités existantes non réinitialisées, audit des accès ; import HTTP repris par référence/image immutable ; simulation via commandes métier conservées avant leur soumission. Les scripts de développement refusant la production restent inchangés. Les magasins portent le préfixe `DÉMO —`, les lots `DEMO-`, les comptes utilisent un domaine `.invalid`, sans invitation à un commerce réel.

Validation isolée acquise : 51 produits, 44 images traitées et vérifiées, 5 magasins/2 organisations/7 comptes démo ; 151 commandes acceptées couvrant 100 ventes, corrections/retours, dégâts, cadeaux et commandes/livraisons. Le rejeu complet conserve les résultats des opérations. 7 tests des garde-fous d’import et 6 tests de supervision réussis. Un premier laboratoire utilisait un répertoire caché pour les médias, refusé par la protection `sendFile` : déplacement vers un répertoire de test non caché, sans affaiblir cette protection. MFA du compte de test configurée avant reprise. Sur le VPS, la copie Docker directe a été refusée par le système de fichiers en lecture seule ; le transfert opérateur utilise son `/tmp` déjà prévu, sans changer le durcissement du conteneur.

Supervision indépendante préparée dans GitHub Actions, compte SSH limité au rapport technique installé et testé, destinataire d’infrastructure confirmé par l’utilisateur. SMTP, clés et destinataire restent dans les secrets du dépôt. HTTPS et rapport hôte réussis ; test de remise depuis le runner distant encore à exécuter. Détails dans [supervision](operational-monitoring.md).

L’utilisateur confirme la réception des emails précédents **dans Spam** et les résultats **SPF PASS, DKIM PASS, DMARC PASS**. Cela confirme l’authentification du domaine mais ne permet pas d’attribuer le classement à une cause précise ni de garantir la boîte principale. Aucun changement DNS arbitraire effectué.

Le relevé VPS trouve environ 28 Gio libres, six conteneurs BioBalance sains, une sauvegarde récente et une maintenance système avec redémarrage en attente. Le serveur héberge aussi d’autres applications. Les échecs du service Certbot global concernent six anciens certificats d’autres domaines ; le certificat BioBalance est valide. Charge cible, restauration après import et maintenance coordonnée restent à consigner après exécution. Les appareils physiques et le pilote humain ne sont pas remplacés par les données de simulation.

### Complément confirmé : tarifs de démonstration

Les sept prix manquants peuvent être fictifs, sur autorisation explicite de l’utilisateur. Sept images correspondantes supplémentaires ont été trouvées et vérifiées ; les tarifs portent « prix démo » dans le nom et la description. Le [relevé du catalogue](catalogue-simulation.md) distingue sources tunisiennes et simulation. L’amendement est séparé du premier import et respecte sa version ; son rejeu local ne double pas les cinq réceptions complémentaires. Vérification locale : 51 produits/images, 39 EAN, 51 configurations dans chacun des cinq magasins, stocks/versions/points/réservations cohérents. 14 tests d’import/amendement et 6 tests de supervision réussissent.

Les 151 opérations de la simulation initiale sont maintenant acceptées sur le VPS. L’application des sept tarifs complémentaires et les vérifications de restauration après import sont en cours au présent relevé.

La supervision distante a réussi : première exécution `35755117973`, email de diagnostic accepté par SMTP ; seconde `35755455044`, état précédent restauré et aucun email répété en situation saine. La réception en boîte principale reste distincte de cette preuve. Le pipeline complet [35755063945](https://github.com/haider0708/bio-balance-app/actions/runs/35755063945) est réussi pour le commit `2750fdd` : backend, Android, parcours Android et iOS non signé.

Sauvegarde des clés Android préparée hors dépôt : OpenPGP AES-256 avec clé de récupération aléatoire, export des deux certificats vérifié, sept fichiers déchiffrés identiques aux originaux. Aucun fichier de clé n’est régénéré. La copie indépendante par le propriétaire demeure à réaliser ; deux fichiers sur le même ordinateur ne couvrent pas sa perte.

### Qualification VPS : correction des lectures volumineuses

Le premier essai du laboratoire complet (500 magasins, 5 000 comptes métier, 300 000 lots et deux millions de ventes) ne satisfait pas les seuils. PostgreSQL sature sous les quotas prévus ; ses historiques, stocks, versions et points restent cohérents après l’essai. Ce résultat échoué est conservé. Des diagnostics SQL ont été exécutés pendant cette passe : elle sert au diagnostic, pas à une mesure d’acceptation finale.

Deux causes sont vérifiées par les plans d’exécution : l’estimation des politiques RLS conduit les ventes récentes à lire/trier environ 4 000 lignes pour en retourner 100 ; le classement applique une fonction sur chaque date au lieu d’une borne indexable. Une migration conserve les droits SELECT/écriture et évalue le contexte transactionnel une fois par requête. Le classement utilise les bornes UTC du mois local, inclusif/exclusif, avec changements d’heure corrects. Aucune donnée ni historique n’est réécrit.

Validation avant image : compilation et formatage réussis, 25 tests d’intégration, 14 tests d’audit et 13 tests de sécurité réussis. Les trois nouvelles régressions couvrent absence/changement de contexte, refus d’écriture hors magasin y compris en lecture admin, bornes de mois à Tunis et à New York avec changement d’heure, dépenses exclues et points négatifs. La nouvelle mesure complète et son installation restent à consigner après exécution. Le commit antérieur `a7ff2b1` passe les quatre jobs CI (`35769095754`).

Le propriétaire demande de limiter la suite à BioBalance : aucune réparation de la base MySQL d’un autre site, mise à niveau globale ou redémarrage de l’hôte partagé ne sera effectué dans cette phase.

### Lectures cohérentes et transactions métier sous concurrence

La qualification longue découvre aussi une saturation du suivi des prédicats PostgreSQL : agrandir sa mémoire seule ne suffit pas lorsque tous les écrans utilisent des transactions sérialisables. Les lectures de magasin et leurs pages persistées utilisent maintenant un instantané `RepeatableRead`, avec les mêmes contrôles de compte/session/appartenance et le même contexte RLS dans la transaction. Le stock, les ventes, points, réservations, configurations et autres commandes conservent `Serializable` et leurs reprises bornées. Seules les métadonnées de pagination peuvent être écrites dans le chemin d’instantané.

La nouvelle régression exécute une écriture concurrente pendant la lecture, vérifie la stabilité de l’instantané, la visibilité au prochain appel, le refus après retrait d’accès et le maintien de `Serializable` pour les commandes. Validation locale : 26 tests d’intégration, 10 de domaine/reprise, 14 d’audit et 13 de sécurité réussis. Le pipeline précédent `35771540115` est réussi pour les quatre jobs de `6a43944`. Les essais de CPU/réplicas et les résultats intermédiaires échoués restent conservés ; ils ne sont pas des passes d’acceptation.

### Configuration de capacité et client externe

Le commit `2c89538` passe les quatre jobs de [CI 35775917105](https://github.com/haider0708/bio-balance-app/actions/runs/35775917105), dont les parcours Android et iOS non signé. Les contrats HTTP et les deux reprises mobile/API réussissent aussi en local.

La nouvelle passe longue ne présente plus d’erreur de mémoire partagée et tous les contrôles de stock, versions, points et révisions réussissent. Avec le générateur sur le VPS, les lectures/écritures à 100 req/s sont à 66,59/142,97 ms p95 ; le pic reste à 448,92/817,35 ms, avec une commande demandant une reprise et 57 itérations non émises. Ce résultat reste **échoué**. Le profil de processus confirme la concurrence CPU entre PostgreSQL, les API et le générateur.

L’override partagé prépare quatre processus API héritant des mêmes contrôles et permissions, PostgreSQL à quatre CPU et Nginx à 0,5 CPU. Les réponses JSON de consultation peuvent être compressées au niveau 1 ; les routes d’identité sont exclues. Le moniteur lit les services attendus depuis Compose. Syntaxe Compose/Nginx/shell et six tests de supervision réussis. Le client de qualification externe conserve les seuils, la vérification TLS, les gardes de ressources, l’arrêt borné et le contrôle des écritures ; sa mesure complète puis l’installation restent à consigner. Aucune intervention sur les autres sites.

La CI complète `35778381586` réussit pour l’outillage et l’override `2a4a3f3`. Le premier client externe n’envoyait pas `Accept-Encoding` : k6 ne le négocie pas automatiquement. Un contrôle réel compare les deux requêtes et confirme la décompression correcte avec `gzip`. Le harnais demande désormais gzip explicitement. Le transfert complet tombe d’environ 1,6 Go à 316 Mo, sans rejet HTTP ou métier ; le pic de lecture reste à 352,83 ms avec le trajet réseau inclus, contre 516,15 ms pour les écritures. Les 27 itérations non émises gardent ce résultat en échec. Les traces montrent de brèves périodes de throttling du proxy et la création de VU pendant le pic. Nginx est porté à un CPU, le client externe prépare 200 VU pour le pic, et une phase de test est envoyée au journal du laboratoire pour comparer temps serveur et transport. Aucun seuil de latence, volume de requêtes ou contrôle métier n’est assoupli. Les métriques de la dernière passe restent à renseigner après exécution.

### Connexions persistantes et reprise du protocole de synchronisation

Un 502 isolé correspond à une connexion amont réutilisée au moment où Node la fermait ; aucune API n’a redémarré et PostgreSQL ne présente plus d’épuisement de mémoire partagée. Nginx retire maintenant ses connexions amont après quatre secondes, avant les cinq secondes configurées dans Node. Les configurations Nginx dédiées et partagées suivent la même règle.

Le scénario conserve désormais le même pool de clients, ses connexions et ses curseurs pendant le passage instantané de 100 à 200 req/s. Les premières versions créaient de nouveaux clients pour le pic ; leurs résultats restent des preuves de stress de reconnexion, avec leurs seuils échoués. La première mesure continue satisfait les latences (lectures/écritures p95 : 136,91/238,70 ms en régime soutenu, 189,37/388,86 ms en pic), sans erreur HTTP ni itération perdue, mais laisse une soumission non acceptée au premier essai : le résultat complet reste échoué.

Le harnais vérifie maintenant la reprise prévue par le protocole : seules les réponses `retryable` avec l’identifiant attendu peuvent être réémises, au plus deux fois, avec exactement le même JSON. Les erreurs terminales, identifiants inattendus, réponses non JSON et reprises épuisées restent des échecs. Compteur de reprises conservé, latence métier incluant leur attente et mêmes seuils de 700 ms ; les requêtes supplémentaires restent dans les métriques HTTP. Quatre tests du harnais réussissent et sont ajoutés à la CI. La mesure complète avec cette vérification est en cours.

La passe complète suivante accepte 3 618 ventes et 35 998 requêtes, sans erreur HTTP, rejet métier ou itération perdue ; tous les historiques/projections restent cohérents. La lecture en pic échoue néanmoins : 456,22 ms côté client, 401 ms dans Nginx. Les écritures restent à 676,87 ms côté client. Les compteurs cgroup montrent environ six fois plus de temps de throttling pour api3/api4 limitées à un CPU que pour api1/api2 à 1,5 CPU, sur des durées de vie comparables. Les quatre HTTP reçoivent donc le même plafond de 1,5 CPU, sans changer PostgreSQL, le scénario ou les seuils. La répétition de validation reste en cours.

La configuration uniforme passe la qualification complète : **35 999 requêtes**, **3 614 ventes acceptées**, zéro HTTP en échec, rejet métier, reprise nécessaire ou itération perdue. Sur le client externe, les p95 lecture/écriture sont **122,36/200,47 ms** à 100 req/s et **277,35/549,46 ms** à 200 req/s ; la durée métier des ventes en pic, attentes comprises, est de **550 ms**. Les contrôles de stock, versions, points, révisions et identités passent sur **2 041 301 ventes**. Les anciens échecs sont conservés ; ce résultat porte sur le scénario à connexions persistantes, pas sur une tempête de reconnexions ni sur des téléphones physiques.

## Clôture catalogue et exploitation BioBalance — 22 septembre 2026

- Images API/média **`2c89538`**, configuration **`3be5389`**, 14 migrations appliquées après sauvegarde. Huit services sains ; les quatre API ont chacune 768 Mio/1,5 CPU. Les quatre jobs de [CI 35784854922](https://github.com/haider0708/bio-balance-app/actions/runs/35784854922) passent. Le pipeline précédent `35783449584` a été annulé avant la fin du dernier parcours Android ; il n’est pas compté comme réussi.
- 51 produits/images, 39 EAN, 44 tarifs vérifiés et sept tarifs marqués « prix démo » installés. Deux déodorants séparés ; douze EAN manquants non inventés. Cinq magasins fictifs, sept comptes, 267 lots, 100 ventes/110 révisions, 392 mouvements et 115 écritures de points. Aucun commerce réel contacté.
- Après installation : HTTPS, MFA admin, déconnexion, refus interorganisations/fausse organisation, médias protégés, checksum et ranges vidéo passent. Les 51 produits restent présents et les cinq magasins ont stocks/versions/points/réservations cohérents.
- Retour à l’ancienne image `2b3769b` testé sur la base isolée avec les 14 migrations : lecture, refus d’un autre magasin et d’une autre organisation, vente et résultat idempotent passent ; les ledgers restent cohérents. Le premier probe utilisait un propriétaire autorisé à plusieurs magasins et attendait à tort un refus ; le probe final utilise un vendeur sans cette autorisation. Aucune permission applicative n’a été modifiée pour ce test.
- Sauvegarde finale **`20260922T214318Z-fb17bd65`** restaurée : **53 médias** vérifiés en taille/SHA-256 et **17 tables métier** identiques par compte/empreinte de lignes. Base/fichiers temporaires de restauration retirés. Le premier lancement du vérificateur opérateur en utilisateur applicatif ne pouvait pas lire son fichier root 0600 ; il a été exécuté avec l’identité opérateur prévue, sans modifier les permissions du service.
- Laboratoire de charge supprimé avec ses volumes après archivage local de 331 éléments, y compris les essais échoués. SHA-256 de l’archive : `e8c9e4fb49e15b35096570f7a479b8f2eceb58707b03cd614bd18aadf1f7565e`. Anciens couples d’images `6a43944`/`caa50b4` supprimés ; images courante/précédente conservées. Tunnel et API locale du test fermés.
- **29,26 Go libres**, occupation 82,4 %, environ **4,49 Mio de backups**, plafond 4 Gio et réserve 10 Gio. Moniteur local sain. Exécution cron réelle `35776577391` avec incident disque observée ; contrôles externes **`35788371179` / `35788470485`** sains après nettoyage, second email de rétablissement accepté par SMTP. Renouvellement ACME dédié et hook Apache vérifiés précédemment. Aucun upgrade global, reboot ou réparation MySQL des autres sites dans cette clôture.

[Relevé de préparation](vps-readiness-2026-09-22.md) et [preuve structurée](../tests/deployment/catalog-operations-evidence-2026-09-22.json). Données métier réelles, téléphones physiques, signature Apple/Play, copie indépendante des clés et pilote humain restent les validations ouvertes. La mesure réussie ne qualifie pas une reconnexion massive ; les anciens échecs correspondants sont conservés. Sauvegardes hors VPS, haute disponibilité et notifications OS app fermée restent reportées. Les messages précédents sont reçus dans Spam malgré SPF/DKIM/DMARC PASS ; leur placement Gmail n’est pas déclaré résolu.


## 23 septembre — retour utilisateur sur Samsung, 1.1.1+5

[Suivi de correction](phone-feedback-2026-09-23.md) : récupération courte et retour connexion, un sélecteur de groupe, retour Android, formulaires, cache photos, commandes par étape, magasin/vendeur dans les ventes, invitations uniques et affectation multiple des vendeurs. Données installées et contrats antérieurs conservés ; résultats de livraison dans ce suivi.

## 2026-09-23 — Installations indépendantes et remise à zéro pour essai manuel

À la demande du propriétaire, ajout des configurations Android Admin / Responsable / Vendeur (v1.1.5+9), avec identifiants, stockage et sessions séparés. Même code métier, mêmes contrôles serveur et mêmes certificats de signature ; aucun privilège ni compte de test intégré. Guide : `docs/manual-role-testing.md`.

Préparation de la remise à zéro limitée à BioBalance : sauvegarde complète, restauration isolée avec 104 fichiers média vérifiés, répétition du script transactionnel et refus vérifié d’une mauvaise confirmation ou d’un nombre de produits inattendu. Les 51 produits, leurs 51 médias et l’administrateur existant sont préservés exactement ; sessions et données de démonstration sont retirées. Les contrôles d’immutabilité et les migrations restent actifs. Une trace de maintenance identifie la sauvegarde.

Validation du code : analyse Flutter sans anomalie ; 252 tests Flutter réussis, 4 tests dépendants de fixtures ignorés ; 38 tests Python de release réussis. Les trois APK signés sont installés sur le Samsung SM-G975F, v1.1.5+9, avec trois UID Android distincts et trois écrans de connexion vérifiés. Le cache de l’ancienne installation a été effacé explicitement pour ce reset ; aucun effacement automatique n’a été ajouté au code. Aucun crash Flutter/Android observé dans les processus inspectés. Source : `955684dcec6136fce8edacd9f51ede37286be4b2`.

Remise à zéro réelle confirmée : sauvegarde `20260923T165738Z-f086e3d0`, 51 produits/51 médias/1 administrateur préservés, zéro groupe/magasin/vente/stock/commande/formation. Mot de passe et MFA inchangés, anciennes sessions révoquées. Les 102 originaux/miniatures de catalogue correspondent à leur SHA-256 ; deux fichiers de formation de test et un export obsolète ont été retirés. Les huit services Compose sont sains, HTTPS `/health` répond `ok`, et les timers sauvegarde/supervision/TLS sont actifs. Le laboratoire de restauration créé pour cette intervention a été supprimé. Les autres applications du VPS sont inchangées.

Preuves : `tests/deployment/manual-testing-evidence-2026-09-23.json`. La CI GitHub `35892569971` est enregistrée séparément des vérifications locales ; les jobs encore actifs au relevé ne sont pas comptés comme réussis. Les comptes responsable/vendeur doivent être créés par invitation pendant le test manuel.
