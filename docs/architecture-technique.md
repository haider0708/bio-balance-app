# BioBalance — Architecture technique

Référence : plans approuvés les 21 et 23 septembre 2026. Voir [spécification](specification-fonctionnelle.md), [contrat OpenAPI](../contracts/openapi/biobalance.json), [état de réalisation](implementation-status.md) et [exploitation](runbook.md).

## Structure

Monorepo avec Flutter/Dart et NestJS/TypeScript. PostgreSQL est la source officielle ; Drift/SQLite permet l’enregistrement local. Le backend est un monolithe modulaire avec un worker séparé et un processus média contraint. Aucune dépendance à Redis n’est nécessaire.

```text
apps/mobile/lib/
  domain/models/                 objets immuables et Money
  domain/repositories/           contrats
  domain/use_cases/              enregistrement métier local
  data/services/api/generated/   transport généré depuis OpenAPI
  data/services/local_database/  Drift, migrations SQLite
  data/repositories/             cache, opérations, réconciliation
  ui/core/                       thème, composants et formulaires
  ui/features/                   MVVM par fonctionnalité
apps/api/src/
  modules/identity/              comptes, invitations, sessions, MFA
  modules/tenancy/               organisations, magasins, appartenances
  modules/catalog/               catalogue et import validé
  modules/operations/
    domain/                     valeurs, ventes et contrats de commandes
    application/                cas métier et ports transactionnels
    infrastructure/             implémentation Prisma du journal
    http/                       adaptateur de synchronisation
  modules/training/             contenus et médias
  modules/notifications/        annonces et notifications
  modules/reporting/            supervision et exports
  shared/                       erreurs, Money, contexte DB et HTTP
apps/api/prisma/migrations/      migrations versionnées et contraintes
contracts/openapi/               contrat exporté
infrastructure/                  environnements Docker
scripts/                        génération, restauration et exploitation
```

Le module transactionnel `operations` réunit les cas ventes, inventaire, livraisons et récompenses derrière `UnitOfWork`/`Ledger`. Il est partagé entre les commandes en ligne et celles issues du téléphone. Les classes métier n’importent ni NestJS ni Prisma. Les contrôleurs valident les requêtes et appellent les services ; les widgets n’écrivent pas dans PostgreSQL ou SQLite.

Le mobile utilise MVVM, Provider, `ChangeNotifier`, objets d’état immuables et injection par constructeur. Les DTO générés restent distincts des objets de domaine. Le transport utilise Dio. Drift ouvre SQLite dans un isolate avec journal WAL ; la file et les brouillons appartiennent au compte et magasin d’origine.

## Versions

Flutter stable **3.47.5**, Dart **3.13.4**, Node **24.21.0**, PostgreSQL **17**. NestJS **12.0.4**, Swagger **12.0.1**, Prisma **7.10.0**. Versions résolues des bibliothèques dans `package-lock.json` et `apps/mobile/pubspec.lock`. `.fvmrc` et `.nvmrc` fixent les runtimes. Le code généré Drift et le contrat sont conservés pour les builds reproductibles.

## Isolation et intégrité

L’identité est dérivée de la session opaque ; les rôles reçus du client ne sont pas utilisés. Les permissions sont revalidées dans la transaction. Les opérations portent organisation et magasin, avec clés étrangères composites. Le rôle PostgreSQL applicatif n’est ni superutilisateur ni propriétaire des tables, et ne possède pas `BYPASSRLS`.

Les politiques RLS utilisent un contexte `SET LOCAL` via `set_config(..., true)` dans la transaction de la requête. Les lectures globales admin passent par un service explicite, contrôlé et audité ; leurs politiques n’autorisent pas de mutations globales.

Une opération métier enregistre atomiquement l’objet, sa révision, les mouvements, les écritures de points, les projections de solde, l’audit, le résultat idempotent et le changement à synchroniser. Les notifications durables sont créées dans la transaction ; les appels SMTP se font ensuite dans le worker ; les notifications sont consultées dans la boîte VPS.

Identifiant d’opération stable + hash canonique du contenu + acteur : réutiliser un identifiant avec un contenu différent est un conflit. Les versions évitent l’écrasement de corrections concurrentes. Les transactions sérialisables sont reprises de manière bornée sur conflits PostgreSQL `40001`/`40P01`, y compris leur représentation par l’adaptateur Prisma.

Le compteur de changements par magasin est verrouillé jusqu’au commit. Les historiques de stock, révisions, points, réceptions, audit et opérations acceptées sont protégés contre `UPDATE`/`DELETE` par PostgreSQL.

## Stock et points

Les lots ont une identité déterministe UUID v5 dérivée du magasin, produit, numéro de lot et date, permettant de référencer hors ligne un lot créé par une réception précédente. Les lots existants conservent leur identité. Les unités sont entières ; les montants et soldes PostgreSQL utilisent `bigint`, transporté sous forme de chaîne JSON.

**Le barème est choisi lors de la première acceptation serveur, jamais imposé par le téléphone.** La révision conserve le taux attribué aux lignes existantes. Les cadeaux débitent le stock sans crédit de vente. Les réservations réduisent les points disponibles, avec déduction définitive à la remise.

## Sécurité et médias

Argon2id pour les mots de passe ; seuls les hash des sessions et codes d’invitation/récupération sont stockés. MFA TOTP administrateur via `otpauth`, secret chiffré AES-GCM par une clé d’environnement. Limitation des tentatives et expiration des codes. Les tokens du mobile restent dans le stockage sécurisé du système.

Les téléversements sont bornés, identifiés par UUID et écrits par fragments à un offset validé. Le worker revalide le fichier et produit un média traité. Le HTML est assaini avant stockage. Les médias restent privés ; l’API contrôle l’accès et Nginx utilise une destination interne, avec support des plages vidéo.

L’audit du 22 septembre centralise les transactions globales dans `Database.authenticated`, avec relecture de la session et du rôle. L’admission Argon2 et celle des corps binaires sont bornées par processus. Les médias réservent leur capacité en transaction et conservent des reçus de fragments pour les réponses perdues. Les liens de compte utilisent des codes manuels ou des associations HTTPS vérifiées. Un refus de session confirmé est conservé sur le téléphone sans effacer le travail en attente. Voir [audit et corrections](audit-2026-09-22.md).

## VPS

Référence à valider : Ubuntu 24.04, 8 vCPU, 16 Go RAM, 200 Go SSD/NVMe. Docker Compose déploie Nginx, deux API stateless par défaut, le worker de notifications, le worker média et PostgreSQL sans port public. L’override du VPS partagé go2code configure quatre API ; sa topologie et ses limites sont détaillées dans [le relevé de qualification](vps-readiness-2026-09-22.md). Données et médias utilisent des volumes persistants locaux.

Les environnements sont distincts. Images immuables, migration explicite avant bascule, journalisation bornée, secrets hors dépôt. SMTP nécessite ses identifiants de déploiement. Firebase est retiré ; les notifications téléphone en arrière-plan sont reportées.

Sauvegarde locale : dump PostgreSQL puis copie des médias immuables, checksums, restauration dans une base isolée. Les sauvegardes hors serveur sont reportées à la demande du propriétaire. Il n’y a aucune promesse de haute disponibilité ni de récupération après perte complète du VPS dans cette phase.

## Validation

Les seuils de performance du plan sont des **critères de recette**. La charge API et SQLite ont été mesurées localement (voir `performance-evidence.md`) ; la qualification du VPS est documentée dans `vps-readiness-2026-09-22.md` ; celle des téléphones physiques reste en attente. Les tests unitaires, transactionnels et de reprise locale sont complétés par des parcours Android/iOS, profils sur appareil physique, tests de charge et restauration. L’état des vérifications et les éléments non terminés doivent rester visibles dans le registre de réalisation.

### Synchronisation v2 et stockage local v3

Les commandes v1 existantes gardent leur payload et identifiant. Les nouvelles commandes v2 déclarent leurs dépendances ; les résultats acceptés exposent un curseur et les versions affectées. `/v1/sync/status` vérifie une soumission incertaine sans rejouer ses effets et fournit un watermark conservateur pour les anciens résultats. Le client conserve l’effet provisoire jusqu’à l’application atomique d’un état serveur qui inclut l’opération. Les retries sont persistés avec jitter et plafond de cinq minutes.

Le snapshot de lecture protocole 3 matérialise les pages supplémentaires dans la même transaction sérialisable que son curseur. Les pages expirent après cinq minutes et vérifient compte, magasin et permissions à chaque lecture ; une expiration ne touche jamais l’outbox. Les projections de stock sont des opérations métier Dart, dont un dommage produit deux incréments de version.

Les demandes de récompense, commandes non terminées, livraisons en cours et récompenses utilisent également ces pages immuables, y compris lors des rafraîchissements incrémentaux. Une page reste bornée à 200 éléments ; les opérations non terminées ne disparaissent pas derrière une limite arbitraire de l’historique récent. Les projections initiales sont regroupées dans une seule requête SQL ; les appels sur la même transaction restent séquentiels.

### Contrats et repositories typés

`shared/contracts` définit les schémas publics et partage les validateurs Zod des requêtes avec les contrôleurs. Toute route sans contrat échoue à la génération. Le client Dart génère les objets immuables, unions et signatures typées ; les repositories les adaptent aux modèles du domaine. L’audit reste un document JSON extensible. Les envois d’anciennes commandes conservent le payload brut persistant, sans réinterprétation par les nouveaux DTO.

`npm run test:contracts` vérifie les 45 endpoints via une API/PostgreSQL isolés et compare les réponses réelles après décodage/réencodage Dart. `scripts/check-contract-drift.sh` régénère puis compare les fichiers versionnés. Les overrides `@prisma/config → deepmerge-ts 8.0.2` et `prisma → mysql2 3.24.4` corrigent des dépendances CLI sans passer à Prisma prerelease ; génération et migrations ont été revérifiées.


### Preuves de déploiement et distribution

Le Compose limite les credentials par service : compte propriétaire uniquement pour PostgreSQL et migrations, compte restreint pour les applications, SMTP uniquement pour le worker concerné. Les remplacements d’API utilisent la résolution DNS Docker par Nginx. La reprise média persiste l’ETag opaque reçu du proxy et vérifie toujours longueur/SHA-256 avant lecture hors ligne.

`tests/deployment/run.sh` vérifie un environnement isolé complet, une restauration avec médias traités et le retour à une version applicative compatible. `scripts/build-mobile-release.sh` sépare compilation sans credentials et signature avec configuration de plateforme. Le package contient des preuves et un état de diffusion explicite ; la compilation ne valide ni les plateformes ni le pilote. Voir `release-gates.md` et `pilot-plan.md`.

## Renforcement de sécurité et distribution

Voir [sécurité et signatures](security-hardening.md) : certificats Android publics versionnés, clés privées hors dépôt, APK/AAB signés séparément, transport limité à une origine HTTPS et budgets PostgreSQL partagés entre sessions/API. Firebase est retiré conformément à la décision du 22 septembre ; la boîte de notifications demeure hébergée sur le VPS. L’attestation distante des appareils reste à configurer et ne sert pas de prétexte à faire confiance au client.

## Présentation mobile compacte

`CompactRow`, `MetricStrip`, `BottomAction` et `WorkspaceNavigation` centralisent les lignes, indicateurs, validation de formulaire et adaptation de la navigation. `OptionField` expose une sélection contrôlée par le formulaire, recherchable et compatible avec la restauration de brouillons. Les listes de collections restent paresseuses ; les pages secondaires écoutent leur modèle pour afficher les changements synchronisés sans navigation supplémentaire. Ces composants n’accèdent pas à la base et ne déplacent pas les règles transactionnelles dans l’interface. Voir [la passe UX](mobile-ux-2026-09-22.md).


## Groupes, reporting et images — 23 septembre 2026

`Organization.id` reste l’identifiant interne du groupe. `GroupService` centralise les autorisations de création et l’équipe de groupe ; les invitations typées conservent les anciens contrats pour la transition. Les dernières appartenances actives sont protégées dans une transaction verrouillant le groupe. Les lectures de groupe emploient un instantané et ne prennent pas ce verrou d’écriture. Les nouvelles API n’acceptent jamais un rôle déclaré par le téléphone.

`ScopeViewModel` conserve un contexte réseau/groupe/magasin indépendant de `WorkspaceViewModel`, qui gère le cache et la synchronisation opérationnelle. Les détails capturent leurs identifiants et ne sélectionnent pas silencieusement un autre magasin. Le chargement d’une commande depuis le réseau ne reconstruit pas la route. Sélections, tutoriels, brouillons et caches utilisent le stockage local existant sous une clé de compte/contexte ; aucune réinterprétation de l’outbox ni migration destructive SQLite.

`SalesContribution`, `SalesDay` et `SalesProductDay` sont des projections PostgreSQL transactionnelles. Un trigger sur les changements de vente couvre aussi les anciens serveurs pendant le déploiement compatible. Le backfill parcourt les identifiants par lots de 1 000, verrouille les ventes concernées et applique uniquement les contributions manquantes ou de version différente. Sa réconciliation indépendante compare lignes/retours autoritaires, totaux journaliers et produits. Les dashboards lisent ces projections, sous RLS, sans télécharger les historiques de tous les magasins sur le téléphone.

Les exports figent leur résultat complet au démarrage du traitement, puis écrivent par lots bornés. Cinq jobs en attente maximum, un export actif par compte, 2 millions de lignes/256 Mio maximum, expiration 24 heures. Les droits et la session sont vérifiés avant traitement, pendant les lots et au téléchargement. Le volume `exports` est distinct des médias, accessible en écriture au worker et en lecture aux API. Ces fichiers temporaires ne sont pas des sauvegardes métier.

Les images traitées possèdent une miniature PNG 384 px, sa taille et SHA-256. Le cache du téléphone est lié au compte, borné à 64 Mio et trois transferts ; 48 instantanés de dashboard par compte sont conservés avec éviction limitée à ces résumés. Il ne supprime ni l’outbox ni les vidéos téléchargées. Les images de groupe passent par le même contrôle de propriétaire, traitement et autorisation que les autres médias.

Les quotas généraux sur comptes authentifiés ont été retirés. Les limites identité/récupération, taille des corps et téléversements, concurrence des jobs, autorisation et protection Nginx/Cloudflare restent actives. Le worker conserve SMTP TLS ; le laboratoire utilise sa propre autorité de test, jamais une désactivation de vérification TLS.
