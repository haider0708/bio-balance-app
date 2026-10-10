# BioBalance

The app that runs the BioBalance network of parapharmacies: points of sale and their teams, stock, restocks through grossistes (warehouses), sales and the rewards salespeople earn. French and English. Android and iOS (Flutter), NestJS and PostgreSQL behind it.

**Who uses it:** the *admin* approves and supervises everything; three *responsables* (Nord, Centre, Sud) run their region; *grossistes* are warehouses of a region, handled by the admin and the responsable (they have no account); *team members* record sales and see what each sale earns them. See the [functional specification](docs/functional-specification.md).

```
apps/api      server: NestJS 12, Prisma 7, PostgreSQL 17 (row-level security keeps regions apart)
apps/mobile   Flutter app (Riverpod, go_router, French/English)
infrastructure/production   Docker image, compose, Nginx, Apache/Cloudflare notes, systemd timers
scripts       deploy, backup, restore check, monitoring, TLS, catalog import
data          the initial catalog: 51 products with photos
docs          specification, architecture, API reference, runbook, release notes
```

## Run it locally

Needs Node 24, Docker, and Flutter 3.47.5.

```sh
docker compose -f infrastructure/development/compose.yml up -d    # PostgreSQL and Mailpit
bash scripts/install-dependencies.sh
cp apps/api/.env.example apps/api/.env                            # set MFA_ENCRYPTION_KEY: 32 random bytes, base64
npm run db:generate
DATABASE_URL=postgresql://biobalance:local-development-only@localhost:54329/biobalance npm run db:migrate
docker compose -f infrastructure/development/compose.yml exec -T postgres psql -U biobalance -d biobalance -v app_password=local-app-only < scripts/provision-role.sql
npm run dev                                                       # API on :3000
ADMIN_EMAIL=you@example.com ADMIN_SETUP_FILE=/tmp/admin.json node --env-file=apps/api/.env apps/api/dist/bootstrap-admin.js
cd apps/mobile && flutter pub get && flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Mailpit shows the emails on `http://localhost:8029`. Load the catalog with `node scripts/import-catalog.mjs`.

## Check it

```sh
bash scripts/setup-test-db.sh      # isolated test database (name ends in _test)
npm run format:check && npm run build && npm test          # server: 80+ tests incl. region isolation and a month-long simulation
cd apps/mobile && flutter analyze && flutter test           # app: widget tests with a fake server
```

The **contract test** runs the app's real repositories against a real API with a realistic world:

```sh
cd apps/api && FIXTURE_OUT=/tmp/fixture.json npx vitest run test/serve-fixture.test.ts &    # serves until /tmp/fixture.json.stop exists
cd apps/mobile && CONTRACT_FIXTURE=/tmp/fixture.json flutter test test/contract
```

The **on-device flow** drives the real app on an emulator or phone against a real server (sign-in, selling and the Bravo screen, a responsable's region, a responsable shipping an order, the admin approving). A seeding script builds the world through the server's public routes and passes it in:

```sh
flutter test integration_test -d <device> --dart-define=WORLD=<base64 json of the seeded world>
```

## Ship it

[Deploy and operate](docs/runbook.md) · [Build and sign the apps](docs/mobile-release.md) · [Architecture](docs/architecture.md) · [API reference](docs/api.md) · [Security](docs/security.md)
