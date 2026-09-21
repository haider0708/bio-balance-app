# BioBalance — Architecture technique

Référence : plan approuvé le 21 septembre 2026. Voir [spécification](specification-fonctionnelle.md), [contrat OpenAPI](../contracts/openapi/biobalance.json), [état de réalisation](implementation-status.md) et [exploitation](runbook.md).

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

Une opération métier enregistre atomiquement l’objet, sa révision, les mouvements, les écritures de points, les projections de solde, l’audit, le résultat idempotent et le changement à synchroniser. Les notifications durables sont créées dans la transaction ; les appels SMTP/FCM se font ensuite dans le worker.

Identifiant d’opération stable + hash canonique du contenu + acteur : réutiliser un identifiant avec un contenu différent est un conflit. Les versions évitent l’écrasement de corrections concurrentes. Les transactions sérialisables sont reprises de manière bornée sur conflits PostgreSQL `40001`/`40P01`, y compris leur représentation par l’adaptateur Prisma.

Le compteur de changements par magasin est verrouillé jusqu’au commit. Les historiques de stock, révisions, points, réceptions, audit et opérations acceptées sont protégés contre `UPDATE`/`DELETE` par PostgreSQL.

## Stock et points

Les lots ont une identité déterministe UUID v5 dérivée du magasin, produit, numéro de lot et date, permettant de référencer hors ligne un lot créé par une réception précédente. Les lots existants conservent leur identité. Les unités sont entières ; les montants et soldes PostgreSQL utilisent `bigint`, transporté sous forme de chaîne JSON.

**Le barème est choisi lors de la première acceptation serveur, jamais imposé par le téléphone.** La révision conserve le taux attribué aux lignes existantes. Les cadeaux débitent le stock sans crédit de vente. Les réservations réduisent les points disponibles, avec déduction définitive à la remise.

## Sécurité et médias

Argon2id pour les mots de passe ; seuls les hash des sessions et codes d’invitation/récupération sont stockés. MFA TOTP administrateur via `otpauth`, secret chiffré AES-GCM par une clé d’environnement. Limitation des tentatives et expiration des codes. Les tokens du mobile restent dans le stockage sécurisé du système.

Les téléversements sont bornés, identifiés par UUID et écrits par fragments à un offset validé. Le worker revalide le fichier et produit un média traité. Le HTML est assaini avant stockage. Les médias restent privés ; l’API contrôle l’accès et Nginx utilise une destination interne, avec support des plages vidéo.

## VPS

Référence à valider : Ubuntu 24.04, 8 vCPU, 16 Go RAM, 200 Go SSD/NVMe. Docker Compose déploie Nginx, deux API stateless, le worker de notifications, le worker média et PostgreSQL sans port public. Données et médias utilisent des volumes persistants locaux.

Les environnements sont distincts. Images immuables, migration explicite avant bascule, journalisation bornée, secrets hors dépôt. FCM/APNs et SMTP nécessitent leurs identifiants de déploiement.

Sauvegarde locale : dump PostgreSQL puis copie des médias immuables, checksums, restauration dans une base isolée. Les sauvegardes hors serveur sont reportées à la demande du propriétaire. Il n’y a aucune promesse de haute disponibilité ni de récupération après perte complète du VPS dans cette phase.

## Validation

Les seuils de performance du plan sont des **critères de recette**, pas des résultats déjà mesurés. Les tests unitaires, transactionnels et de reprise locale sont complétés par des parcours Android/iOS, profils sur appareil physique, tests de charge et restauration. L’état des vérifications et les éléments non terminés doivent rester visibles dans le registre de réalisation.

### Synchronisation v2 et stockage local v3

Les commandes v1 existantes gardent leur payload et identifiant. Les nouvelles commandes v2 déclarent leurs dépendances ; les résultats acceptés exposent un curseur et les versions affectées. `/v1/sync/status` vérifie une soumission incertaine sans rejouer ses effets et fournit un watermark conservateur pour les anciens résultats. Le client conserve l’effet provisoire jusqu’à l’application atomique d’un état serveur qui inclut l’opération. Les retries sont persistés avec jitter et plafond de cinq minutes.

Le snapshot de lecture protocole 3 matérialise les pages supplémentaires dans la même transaction sérialisable que son curseur. Les pages expirent après cinq minutes et vérifient compte, magasin et permissions à chaque lecture ; une expiration ne touche jamais l’outbox. Les projections de stock sont des opérations métier Dart, dont un dommage produit deux incréments de version.

### Contrats et repositories typés

`shared/contracts` définit les schémas publics et partage les validateurs Zod des requêtes avec les contrôleurs. Toute route sans contrat échoue à la génération. Le client Dart génère les objets immuables, unions et signatures typées ; les repositories les adaptent aux modèles du domaine. L’audit reste un document JSON extensible. Les envois d’anciennes commandes conservent le payload brut persistant, sans réinterprétation par les nouveaux DTO.

`npm run test:contracts` vérifie les 44 endpoints via une API/PostgreSQL isolés et compare les réponses réelles après décodage/réencodage Dart. `scripts/check-contract-drift.sh` régénère puis compare les fichiers versionnés. Les overrides `@prisma/config → deepmerge-ts 8.0.2` et `prisma → mysql2 3.24.4` corrigent des dépendances CLI sans passer à Prisma prerelease ; génération et migrations ont été revérifiées.
