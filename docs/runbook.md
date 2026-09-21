# Exploitation BioBalance

## Environnements et secrets

Développement, staging et production utilisent des bases, médias, clés MFA et projets Firebase distincts. L’API de production refuse de démarrer sans base et clé MFA de 32 octets. Ne jamais incorporer les mots de passe PostgreSQL, SMTP, clés de compte de service Firebase ou clés de signature dans l’application.

Copier `infrastructure/production/.env.example` vers `.env` sur le VPS, chmod 0600, remplacer toutes les valeurs d’exemple. `DATABASE_URL` utilise **biobalance_app** ; `MIGRATION_DATABASE_URL` utilise le propriétaire. `FIREBASE_CREDENTIALS_FILE` désigne un fichier privé monté comme secret. Le worker s’exécute en UID 1000 : rendre son fichier Firebase lisible par cet UID (`chown 1000:1000`, `chmod 0400`). Les API et le worker média ne montent pas ce fichier. Chaque service reçoit uniquement les variables déclarées dans Compose ; les credentials propriétaire/migration restent exclus des API/workers. `SMTP_REQUIRE_TLS=true` impose STARTTLS ; la désactivation est réservée au SMTP local de test.

Garder la clé MFA aussi longtemps que des secrets chiffrés l’utilisent ; elle est nécessaire après restauration de la base. Les répertoires de secrets/certificats et les artefacts privés sont exclus de Git et du contexte Docker.

## Construction et migration

```sh
docker build --target runtime -f infrastructure/production/Dockerfile -t biobalance-api:COMMIT .
docker build --target media -f infrastructure/production/Dockerfile -t biobalance-media:COMMIT .
```

Publier les images sur votre registre et renseigner les tags immuables ou digests dans `.env`. Avant chaque migration : sauvegarde locale complète, restauration isolée vérifiée, lecture de la migration, test staging. Démarrer PostgreSQL puis exécuter le service `migrate` avec `--profile maintenance`. Exécuter `scripts/provision-role.sql` dans la base pour créer le rôle applicatif **NOSUPERUSER NOBYPASSRLS** et ses droits. Ne jamais faire tourner l’API avec le propriétaire de la base.

Créer le premier administrateur avec `node dist/bootstrap-admin.js` dans un conteneur API ponctuel, en fournissant `ADMIN_EMAIL`, `ADMIN_NAME`, `ADMIN_SETUP_FILE` sur un volume privé et la clé MFA. Le fichier produit contient le mot de passe aléatoire et l’URI d’authentification TOTP ; l’importer dans l’application d’authentification et le conserver dans un coffre. Le programme refuse de remplacer un administrateur existant.

## HTTPS et réseau

Ubuntu 24.04 LTS, accès SSH par clés, ports publics 80/443 seulement et SSH restreint aux adresses d’administration. PostgreSQL n’expose aucun port hôte. Adapter `server_name` dans Nginx au domaine API possédé.

Installer certbot sur le VPS puis préparer `/etc/biobalance/tls.env` (0600) avec `COMPOSE_FILE`, `COMPOSE_ENV_FILE`, `API_DOMAIN` et `ACME_EMAIL`. Exporter ces variables dans le shell d’installation et lancer `scripts/tls-bootstrap.sh`. Le script démarre un serveur HTTP temporaire uniquement si nécessaire, obtient le certificat, vérifie sa date et sa correspondance avec la clé, puis installe les fichiers. Le domaine doit déjà pointer vers le VPS et le port 80 être accessible.

Installer les unités `biobalance-tls.service`/`.timer` et activer le timer après démarrage de Nginx. `scripts/tls-renew.sh --dry-run` vérifie ACME ; le hook `tls-install.sh` valide et recharge Nginx. Éviter deux timers concurrents de renouvellement pour le même certificat. Les tests locaux ont utilisé une autorité auto-signée réservée au laboratoire : ils ne remplacent pas l’émission et le renouvellement ACME réels.

Démarrer les deux API, worker notifications/tâches, worker média et Nginx avec `up -d --wait`. Nginx résout les services Docker au cours de leur vie ; remplacer une API à la fois permet à l’autre de servir les requêtes. Les workers terminent leur tâche avant arrêt (60 secondes pour le worker opérationnel, 11 minutes pour un transcodage borné). Vérifier `/health`, authentification, accès intermagasins refusé, réception et vente. Le média est servi par une location interne Nginx après autorisation API ; l’accès direct à `/_media/` doit échouer et une vidéo autorisée doit accepter `Range`.

## Téléphones

Définir `API_BASE_URL` HTTPS au build. La notification push utilise les paramètres Firebase publics via `--dart-define-from-file` : `FIREBASE_APP_ID`, `FIREBASE_API_KEY`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID`. Ils diffèrent pour Android et iOS. Configurer les identifiants `tn.biobalance.app`, APNs dans Firebase et la capacité Push Notifications dans Xcode. Le worker utilise uniquement le compte de service privé côté serveur.

Le bouton « Activer les notifications » demande la permission au moment utile. Le worker exclut les sessions expirées/révoquées avant envoi. Un message déjà confié à la plateforme peut arriver plus tard ; le texte OS reste générique et l’application revérifie l’accès avant de charger le contenu. Les contrôles de caméra, notifications réelles et lecture vidéo doivent être exécutés sur Android et iOS physiques.

La signature Android lit `BIOBALANCE_KEYSTORE`, `BIOBALANCE_KEYSTORE_PASSWORD`, `BIOBALANCE_KEY_ALIAS`, `BIOBALANCE_KEY_PASSWORD`. Vérifier les noms exacts dans `android/app/build.gradle.kts`. iOS demande les certificats/profils Apple sur macOS. Le build debug disponible n’est pas un livrable signé de production.

## Sauvegarde et restauration

Configurer `/etc/biobalance/backup.env` avec `COMPOSE_FILE`, `COMPOSE_ENV_FILE` et `BACKUP_DIR`, absolus. `COMPOSE_PROJECT_NAME` et `COMPOSE_OVERRIDE_FILE` sont optionnels pour un environnement isolé. Installer les unités `infrastructure/production/systemd/biobalance-backup.*` dans `/etc/systemd/system/`, `systemctl daemon-reload`, puis activer le timer. Il crée un dump PostgreSQL et une archive média avec sommes SHA256 chaque nuit ; il ne supprime pas automatiquement d’anciennes sauvegardes.

```sh
COMPOSE_FILE=/opt/biobalance/infrastructure/production/compose.yml BACKUP_DIR=/srv/biobalance-backups scripts/local-backup.sh
COMPOSE_FILE=/opt/biobalance/infrastructure/production/compose.yml BACKUP_PATH=/srv/biobalance-backups/DATE scripts/verify-restore.sh
```

La restauration crée une **nouvelle base isolée**, extrait les médias séparément, vérifie les sommes d’archives, la taille et le SHA-256 de chaque fichier référencé comme prêt. Un ancien média sans empreinte doit être vérifié par le worker avant cette recette ; la restauration refuse de prétendre l’avoir contrôlé. La base et les fichiers restaurés restent disponibles pour inspection. Le script ne remplace pas la production. Pour une restauration réelle, arrêter les écritures, garder une copie de l’état courant, restaurer sur des volumes neufs, vérifier les parcours, puis basculer la configuration.

**Une sauvegarde sur le même VPS ne protège pas de sa perte ou destruction. Sauvegardes hors serveur et haute disponibilité sont explicitement reportées.**

## Surveillance et incidents

- Surveiller santé API/PostgreSQL/workers, espace disque (alerte à 85 %), RAM, CPU, âge de sauvegarde, erreurs de synchro, jobs échoués et latences p95. `scripts/check-vps.sh` contrôle les six services, la RAM disponible (10 % minimum), la charge soutenue, le disque, les sauvegardes et les jobs échoués/en retard/baux périmés. Installer `biobalance-monitor.service`/`.timer` pour un contrôle chaque minute. Relier les échecs d’unité à votre supervision pour acheminer une alerte opérateur ; cet acheminement externe doit être testé sur le VPS.
- Les journaux HTTP contiennent route, durée, statut et identifiant de corrélation, sans mots de passe, corps de requête ni en-tête Authorization. Docker applique une rotation de 5 × 10 Mo par service.
- Les workers utilisent des tâches PostgreSQL avec reprises et huit tentatives maximum. Examiner `Job.lastError` et la cause externe avant de remettre une tâche échouée en attente ; ne pas modifier les journaux métier.
- Les alertes stock et péremption sont recalculées lors des opérations et par contrôles horaires. Les annonces vendeurs sont envoyées volontairement par le responsable.
- En cas de conflit de synchronisation, utiliser « Vérifier et résoudre ». La saisie rejetée reste conservée localement. Ne pas effacer SQLite ni réinstaller l’application tant que des opérations restent en attente.
- Une révocation d’accès laisse les opérations liées à leur compte ; rétablir l’accès si nécessaire pour terminer leur traitement. Ne jamais les envoyer sous un autre utilisateur.

## Retour arrière

Conserver le digest précédent et ses variables d’environnement. Les migrations doivent être compatibles avec le déploiement progressif des deux API. Si seul le code échoue, revenir à l’image précédente après contrôle de compatibilité du schéma. Une migration destructive ne se « défait » pas en remettant une ancienne image : planifier une migration corrective ou une restauration avec interruption, après comparaison des écritures intervenues.

## Portes de sortie

Aucune diffusion générale avant : tests métier/RLS/reprise passants, restauration vérifiée avec médias réels, signatures Android/iOS, tests caméra/push et accessibilité, profils physiques, scénario de charge représentatif, acceptation des trois rôles sur un petit pilote. Étendre ensuite à 50 magasins et enfin 500 suivant les métriques et incidents.

## Diagnostic des workers

`WORKER_CONCURRENCY` borne le worker opérationnel entre 1 et 4 (2 par défaut). Le worker média reste à 1 et ne prend que les tâches média. Chaque tâche porte un bail UUID renouvelable ; une ancienne exécution ne peut pas terminer la tâche après récupération du bail. Les jobs horaires réutilisent leur identifiant d’opération et les envois push conservent leurs reçus par appareil/session.

Examiner `Job.kind`, `key`, `attempts`, `availableAt`, `lockedAt`, `status`, `lastError` sans exporter les payloads (ils peuvent contenir des invitations). Après correction de la cause, relancer un job précis en conservant son `id`/`key`/`payload` : remettre `status='pending'`, `attempts=0`, `availableAt=now()`, `lockedAt=NULL`, `leaseToken=NULL` uniquement si son statut est `failed`. Ne jamais modifier un job courant pour le relancer. Les appels FCM/SMTP restent au moins une fois en cas de réponse externe perdue.

## Recette locale et retour arrière vérifié

`tests/deployment/run.sh` construit et démarre un laboratoire séparé, vérifie droits et volumes, traite une image/vidéo, teste la reprise Flutter derrière Nginx, redémarre les workers, change les certificats et compare une restauration aux enregistrements sources. Voir `tests/deployment/README.md`. Les journaux sont conservés dans `.artifacts/evidence/step11/` ; ne pas publier les credentials, certificats ni backups du laboratoire.

Pour déployer ou revenir au code précédent, sélectionner un fichier d’environnement privé contenant les digests testés puis : migration compatible, `up -d --no-deps --force-recreate --wait api1`, contrôle autorisé du magasin, même commande pour `api2`, puis pour `worker media-worker`. Garder l’autre API disponible pendant chaque remplacement. Contrôler les images effectives, rejouer une opération connue (son résultat doit rester identique), vérifier stock/points/média et les jobs. Ne jamais exécuter `down -v` sur la production pour changer une image. Si le schéma n’est pas compatible, utiliser une migration corrective ou la procédure de restauration avec arrêt des écritures.

La recette locale a testé l’ancien code `a8b4610` avec le packaging runtime corrigé, puis le code actuel sur le même schéma additif. Ce n’est pas une autorisation générale de revenir à n’importe quelle ancienne version. La CI distante et les opérations sur le VPS attendent le dépôt et les accès correspondants.
