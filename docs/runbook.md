# Exploitation BioBalance

## Environnements et secrets

Développement, staging et production utilisent des bases, médias, clés MFA et projets Firebase distincts. L’API de production refuse de démarrer sans base et clé MFA de 32 octets. Ne jamais incorporer les mots de passe PostgreSQL, SMTP, clés de compte de service Firebase ou clés de signature dans l’application.

Copier `infrastructure/production/.env.example` vers `.env` sur le VPS, chmod 0600, remplacer toutes les valeurs d’exemple. `DATABASE_URL` utilise **biobalance_app** ; `MIGRATION_DATABASE_URL` utilise le propriétaire. `FIREBASE_CREDENTIALS_FILE` désigne un fichier privé monté comme secret. Garder la clé MFA aussi longtemps que des secrets chiffrés l’utilisent.

## Construction et migration

```sh
docker build --target runtime -f infrastructure/production/Dockerfile -t biobalance-api:COMMIT .
docker build --target media -f infrastructure/production/Dockerfile -t biobalance-media:COMMIT .
```

Publier les images sur votre registre et renseigner les tags immuables ou digests dans `.env`. Avant chaque migration : sauvegarde locale complète, restauration isolée vérifiée, lecture de la migration, test staging. Démarrer PostgreSQL puis exécuter le service `migrate` avec `--profile maintenance`. Exécuter `scripts/provision-role.sql` dans la base pour créer le rôle applicatif **NOSUPERUSER NOBYPASSRLS** et ses droits. Ne jamais faire tourner l’API avec le propriétaire de la base.

Créer le premier administrateur avec `node dist/bootstrap-admin.js` dans un conteneur API ponctuel, en fournissant `ADMIN_EMAIL`, `ADMIN_NAME`, `ADMIN_SETUP_FILE` sur un volume privé et la clé MFA. Le fichier produit contient le mot de passe aléatoire et l’URI d’authentification TOTP ; l’importer dans l’application d’authentification et le conserver dans un coffre. Le programme refuse de remplacer un administrateur existant.

## HTTPS et réseau

Ubuntu 24.04 LTS, accès SSH par clés, ports publics 80/443 seulement et SSH restreint aux adresses d’administration. PostgreSQL n’expose aucun port hôte. Adapter `server_name` dans Nginx au domaine API possédé.

Obtenir le certificat avec ACME/certbot sur le serveur. La première émission nécessite un serveur HTTP ACME temporaire car Nginx ne démarre pas avant que ses fichiers TLS existent. Déposer `fullchain.pem` et `privkey.pem` dans le dossier `certificates` monté en lecture seule. Configurer le timer certbot et un hook de renouvellement qui recopie les certificats puis exécute `docker compose exec -T nginx nginx -s reload`. Vérifier le renouvellement avec `certbot renew --dry-run` avant lancement.

Démarrer les deux API, worker notifications/tâches, worker média et Nginx. Vérifier `/health`, authentification, accès intermagasins refusé, réception et vente. Le média est servi par une location interne Nginx après autorisation API ; l’accès direct à `/_media/` doit échouer et une vidéo autorisée doit accepter `Range`.

## Téléphones

Définir `API_BASE_URL` HTTPS au build. La notification push utilise les paramètres Firebase publics via `--dart-define-from-file` : `FIREBASE_APP_ID`, `FIREBASE_API_KEY`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID`. Ils diffèrent pour Android et iOS. Configurer les identifiants `tn.biobalance.app`, APNs dans Firebase et la capacité Push Notifications dans Xcode. Le worker utilise uniquement le compte de service privé côté serveur.

Le bouton « Activer les notifications » demande la permission au moment utile. Le worker exclut les sessions expirées/révoquées avant envoi. Un message déjà confié à la plateforme peut arriver plus tard ; le texte OS reste générique et l’application revérifie l’accès avant de charger le contenu. Les contrôles de caméra, notifications réelles et lecture vidéo doivent être exécutés sur Android et iOS physiques.

La signature Android lit `BIOBALANCE_KEYSTORE`, `BIOBALANCE_KEYSTORE_PASSWORD`, `BIOBALANCE_KEY_ALIAS`, `BIOBALANCE_KEY_PASSWORD`. Vérifier les noms exacts dans `android/app/build.gradle.kts`. iOS demande les certificats/profils Apple sur macOS. Le build debug disponible n’est pas un livrable signé de production.

## Sauvegarde et restauration

Configurer `/etc/biobalance/backup.env` avec `COMPOSE_FILE` et `BACKUP_DIR`, absolus. Installer les unités `infrastructure/production/systemd/biobalance-backup.*` dans `/etc/systemd/system/`, `systemctl daemon-reload`, puis activer le timer. Il crée un dump PostgreSQL et une archive média avec sommes SHA256 chaque nuit ; il ne supprime pas automatiquement d’anciennes sauvegardes.

```sh
COMPOSE_FILE=/opt/biobalance/infrastructure/production/compose.yml BACKUP_DIR=/srv/biobalance-backups scripts/local-backup.sh
COMPOSE_FILE=/opt/biobalance/infrastructure/production/compose.yml BACKUP_PATH=/srv/biobalance-backups/DATE scripts/verify-restore.sh
```

La restauration crée une **nouvelle base isolée**, extrait les médias séparément, vérifie les sommes et tous les fichiers référencés comme prêts. La base et les fichiers restaurés restent disponibles pour inspection. Le script ne remplace pas la production. Pour une restauration réelle, arrêter les écritures, garder une copie de l’état courant, restaurer sur des volumes neufs, vérifier les parcours, puis basculer la configuration.

**Une sauvegarde sur le même VPS ne protège pas de sa perte ou destruction. Sauvegardes hors serveur et haute disponibilité sont explicitement reportées.**

## Surveillance et incidents

- Surveiller santé API/PostgreSQL/workers, espace disque (alerte à 85 %), RAM, CPU, âge de sauvegarde, erreurs de synchro, jobs échoués et latences p95. `scripts/check-vps.sh` fournit un contrôle local avec code de sortie ; le connecter à votre système de supervision.
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
