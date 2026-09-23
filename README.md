# BioBalance

Application Flutter en français pour les vendeurs, responsables de groupes et l’administration BioBalance. API NestJS, PostgreSQL et stockage local Drift ; architecture objet avec MVVM, injection par constructeur et règles métier séparées des interfaces.

**État : backend déployé sur https://api.galylio.com et APK Android v1.0.0 signé ; qualification physique, distribution Play/iOS et pilote en attente.** [Télécharger la release Android](https://github.com/haider0708/bio-balance-app/releases/tag/v1.0.0). Voir [l’état détaillé](docs/implementation-status.md), la [spécification](docs/specification-fonctionnelle.md), l’[architecture](docs/architecture-technique.md) et le [runbook](docs/runbook.md).

Dernière refonte : [groupes, tableaux de bord et interface 1.1.0+4](docs/redesign-2026-09-23.md), avec [captures et revue visuelle](docs/screenshot-inventory-2026-09-23.md). La release publique v1.0.0 reste distincte de la nouvelle candidate.

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
bash scripts/install-dependencies.sh
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
# ffmpeg et ffprobe doivent être disponibles dans PATH
npm run test:media
npm run test:notifications
# Flutter/Dart également disponibles dans PATH
npm run test:contracts
npm run test:mobile-sync
bash scripts/check-contract-drift.sh
cd apps/mobile
flutter analyze
flutter test --concurrency=1
flutter build apk --debug
```

Les tests PostgreSQL utilisent **biobalance_test** et un rôle sans privilège de contournement RLS. Ne pas les pointer vers une base de production. Le contrat génère les types de transport Dart ; les objets du domaine restent distincts.

Pour les workers : `npm run worker -w apps/api` ; définir `WORKER_KIND=media` et installer ffmpeg pour le worker média. Les services de production utilisent des conteneurs séparés.

Les icônes et écrans de lancement sont générés depuis le logo fourni par `python3 scripts/generate-brand-assets.py` (Pillow requis). Les images générées sont versionnées.

## Livraison

Voir [la release v1.0.0](docs/releases/v1.0.0.md), [le runbook](docs/runbook.md), [les builds mobiles](docs/mobile-release.md), [les portes de diffusion](docs/release-gates.md) et [le pilote](docs/pilot-plan.md). Le VPS, HTTPS, SMTP authentifié et la restauration locale sont vérifiés. La réception email, la charge du VPS et la restauration de médias sont désormais vérifiées ; Gmail a classé le message dans le spam malgré SPF/DKIM/DMARC valides. Restent l’inscription Play, la signature Apple, les mesures physiques et le pilote. [GitHub Actions](https://github.com/haider0708/bio-balance-app/actions) fournit les résultats CI distants. Les sauvegardes hors VPS et la haute disponibilité sont hors du périmètre convenu.

La [configuration de sécurité et de signature](docs/security-hardening.md) documente les protections, clés privées hors dépôt, certificats publics et validations restantes. Firebase a été retiré ; les notifications sont disponibles dans la boîte interne du VPS.
