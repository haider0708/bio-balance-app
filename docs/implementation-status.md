# État de l’implémentation — 22 septembre 2026

Les corrections de la dernière passe d’audit sont implémentées et vérifiées localement ; l’application n’est pas encore qualifiée pour une diffusion en production. Ce document distingue les fonctionnalités codées des vérifications réalisées.

Dernière passe : [audit final et qualification](final-audit-2026-09-22.md). Les résultats des étapes antérieures ci-dessous sont historiques.

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

## Vérifications réalisées localement

| Vérification | Résultat constaté |
|---|---|
| Compilation TypeScript | Réussie |
| Tests domaine et reprise transactionnelle backend | 10 réussis |
| Tests PostgreSQL réels avec rôle restreint | 22 réussis + 14 régressions d’audit + 4 tests de traitement média réel + 5 tests notifications/workers + 13 tests sécurité |
| Tests Flutter de reprise, migration et dispositions d’écran | 130 réussis ; 2 parcours HTTP, contrats Dart et reprise média HTTPS/Nginx exécutés séparément et réussis |
| Build Android | Debug normal lancé/rechargé et APK/AAB release non signés compilés ; parcours/force-stop/vidéo réussis sur émulateur ; APK/AAB inertes signés vérifiés et installation/mise à jour testées ; signature Apple et appareils physiques en attente |
| Sauvegarde/restauration isolée | Réussie : données métier, image et vidéo traitées ; tailles/empreintes et projections comparées après restauration isolée |
| OpenAPI et génération Dart | 45 endpoints vérifiés sur HTTP réel ; schémas Dart typés générés et aller-retour JSON validé |
| Images Docker et émulateur | Parcours Android et Compose complet local réussis ; API/média, TLS, isolation, reprise et rollback vérifiés |

Un passage des tests PostgreSQL a expiré pendant une forte saturation mémoire de l’hôte par les builds Android. Après arrêt des anciens daemons de compilation devenus inutiles, les 12 tests ont réussi sans allonger leur délai.

Audit du 22 septembre : voir [constats corrigés et preuves](audit-2026-09-22.md). Les APK/AAB release non signés de l’étape 12 précèdent ces corrections ; ils restent des preuves historiques de compilation et doivent être reconstruits avant un pilote.

## Travail restant avant acceptation

- Déploiement/restauration avec médias traités et rollback vérifiés localement ; valider ces procédures sur le VPS cible.
- Parcours UI Android, révocation en cours de saisie, erreur SQLite et force-stop vérifiés ; compléter la recette native iOS et les essais physiques.
- Lecture vidéo hors ligne vérifiée sur émulateur Android ; liens natifs et transferts interrompus sur appareils physiques restent à vérifier.
- Exécuter tests caméra/notifications internes, accessibilité, rotation et stabilité mémoire sur Android/iOS physiques ; compiler iOS sur macOS et produire les builds signés.
- Charge locale 100/200 req/s et benchmark SQLite exécutés (voir étape 10). Rejouer sur le VPS de référence ; démarrage, persistance/recherche et fluidité restent à qualifier sur appareils physiques.
- Renseigner VPS/domaine/SMTP, inscription Play avec la clé locale et signature Apple, valider renouvellement TLS/supervision, puis effectuer le pilote et corriger ses retours.

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
| 8. Notifications/workers | Implémentation et vérification locale terminées ; FCM/APNs réels en attente |
| 9. Parcours complets | Vérification locale terminée sur émulateur Android ; iOS/appareils physiques en attente |
| 10. Performances/appareils | Charge API et SQLite mesurées localement ; VPS/appareils physiques en attente |
| 11. Déploiement/reprise | Compose, reprise et rollback vérifiés localement ; CI distante/VPS/ACME en attente |
| 12. Versions signées/pilote | Préparation locale et APK/AAB non signés terminés ; signatures, iOS et pilote de deux semaines en attente |

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
