# BioBalance

Application Flutter en français pour les vendeurs, responsables de magasins et l’administration BioBalance. API NestJS, PostgreSQL et stockage local Drift ; architecture objet avec MVVM, injection par constructeur et règles métier séparées des interfaces.

**État : implémentation en cours, utilisable en développement. La qualification de production n’est pas terminée.** Voir [l’état détaillé](docs/implementation-status.md), la [spécification](docs/specification-fonctionnelle.md), l’[architecture](docs/architecture-technique.md) et le [runbook](docs/runbook.md).

## Organisation

```text
apps/mobile/lib/
  domain/             Objets, contrats de repositories, cas d’utilisation
  data/               SQLite, synchronisation, client API généré, notifications
  ui/core/            Thème BioBalance, formulaires et composants
  ui/features/        Écrans et view models par fonctionnalité
apps/api/src/
  shared/             Money, erreurs, transactions et sécurité HTTP
  modules/            Identity, tenancy, catalog, operations, training, reporting
apps/api/prisma/       Schéma et migrations PostgreSQL
contracts/openapi/     Contrat REST versionné
infrastructure/        Docker Compose développement et VPS
scripts/               Génération, sauvegarde et restauration
```

## Démarrage local

Installer Flutter **3.47.5**, Node.js **24.21.0**, Docker Compose, Python 3 et les outils Android. Les dépendances exactes sont verrouillées. Utiliser un hôte macOS avec Xcode pour iOS.

```sh
docker compose -f infrastructure/development/compose.yml up -d
npm ci
cp apps/api/.env.example apps/api/.env
npm run db:generate
```

Renseigner `MFA_ENCRYPTION_KEY` dans `.env` avec 32 octets aléatoires encodés en base64. Ne pas versionner ce fichier. Migrer avec le compte propriétaire, puis provisionner le compte applicatif restreint :

```sh
DATABASE_URL=postgresql://biobalance:local-development-only@localhost:54329/biobalance npm run db:migrate
docker compose -f infrastructure/development/compose.yml exec -T postgres psql -U biobalance -d biobalance -v app_password=local-app-only < scripts/provision-role.sql
npm run db:seed -w apps/api
npm run dev
```

Les identifiants de démonstration générés sont dans `.local-credentials.json` (0600, ignoré par Git). Le compte administrateur utilise aussi un code TOTP. Le seed est réservé au développement. Mailpit affiche les invitations sur `http://localhost:8029`.

Dans un autre terminal :

```sh
cd apps/mobile
flutter pub get --enforce-lockfile
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

L’adresse `10.0.2.2` désigne l’hôte depuis l’émulateur Android. Pour un téléphone physique, choisir l’URL HTTPS du serveur de développement. Le mode debug Android accepte le HTTP ; les builds de diffusion doivent utiliser HTTPS.

## Vérification

```sh
npm run build
npm test
scripts/setup-test-db.sh
npm run test:integration
npm run api:contract
python3 scripts/generate-dart-client.py
cd apps/mobile
flutter analyze
flutter test --concurrency=1
flutter build apk --debug
```

Les tests PostgreSQL utilisent **biobalance_test** et un rôle sans privilège de contournement RLS. Ne pas les pointer vers une base de production. Le contrat génère les types de transport Dart ; les objets du domaine restent distincts.

Pour les workers : `npm run worker -w apps/api` ; définir `WORKER_KIND=media` et installer ffmpeg pour le worker média. Les services de production utilisent des conteneurs séparés.

## Livraison

Voir [runbook.md](docs/runbook.md). Restent nécessaires : VPS, domaine API, SMTP, paramètres Firebase/APNs, comptes de signature, tests physiques Android/iOS, tests de charge et validation pilote. Les sauvegardes hors VPS et la haute disponibilité sont hors du périmètre convenu.
