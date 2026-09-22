# BioBalance sur le VPS partagé go2code

Cet override est propre à ce serveur. Apache y sert déjà d’autres sites sur 80/443. Il termine HTTPS pour `api.galylio.com` et transmet vers Nginx sur `127.0.0.1:18081`. Nginx conserve les limites de requêtes, le routage vers les quatre processus API et les médias protégés par `X-Accel-Redirect`.

Les fichiers ne contiennent aucun secret. L’environnement réel reste dans `/etc/biobalance/backend.env` (root, 0600). Commande opérateur : `sudo biobalance-compose …`. Le réseau `172.29.90.0/24` a été vérifié libre avant installation ; ne pas réutiliser cet override ailleurs sans vérifier réseau et ports.

## Cloudflare et HTTPS

- DNS `A api → 146.59.195.61`, proxy activé, TTL automatique ; SSL/TLS **Full (strict)** confirmé pour cet hôte.
- `apache-http.conf` sert les challenges ACME publics et redirige le reste vers HTTPS.
- `apache-https.conf` utilise le certificat Let's Encrypt de cet hôte et inclut `cloudflare-origin.conf`. L’accès HTTPS d’origine est limité aux adresses Cloudflare et au loopback. Aucun changement des restrictions des autres sites.
- `CF-Connecting-IP` est accepté uniquement depuis les plages Cloudflare officielles. L’autorisation utilise l’adresse de connexion originale (`CONN_REMOTE_ADDR`), et non celle fournie dans un en-tête. Apache remplace les autres en-têtes de forwarding ; Nginx ne fait confiance qu’à la passerelle Docker de l’hôte.
- `biobalance-tls.timer` lance un renouvellement limité à `api.galylio.com` deux fois par jour. Le hook `/etc/letsencrypt/renewal-hooks/deploy/biobalance-apache` vérifie Apache et le recharge après renouvellement de ce certificat. Le timer Certbot global des autres sites est conservé ; les verrous Certbot empêchent deux écritures concurrentes. Le résultat du service BioBalance est surveillé séparément.
- Les plages Cloudflare proviennent de `https://api.cloudflare.com/client/v4/ips`, relevées et validées le 22 septembre 2026. Réviser cette liste si Cloudflare annonce un changement, vérifier `apache2ctl configtest`, puis effectuer un rechargement gracieux.
- Ne pas activer de cache forcé ou de challenge navigateur sur les routes API. Les réponses et médias protégés portent `Cache-Control: no-store`. Les clients Flutter/Dart ont été testés. Le contrôle d’intégrité Cloudflare refuse le User-Agent Python générique ; le harnais utilise son identité réelle `BioBalance-Deployment/1.0`.

Pour une modification Nginx montée par fichier, recréer **uniquement** son conteneur après validation syntaxique : remplacer le fichier peut modifier son inode. Ne jamais utiliser `down -v` pour une mise à jour.

## Ressources et exploitation

Plafonds : quatre API de 768 Mio (1,5 CPU pour api1/api2, 1 CPU pour api3/api4), worker 384 Mio/0,5 CPU, média 1 Gio/1 CPU, PostgreSQL 2 Gio/4 CPU, Nginx 128 Mio/0,25 CPU. Les deux processus supplémentaires héritent de la même définition applicative avec `extends`, sans copie des paramètres sensibles. PostgreSQL borne les connexions à 60 et le suivi des prédicats à 1 024 verrous par transaction/512 par relation. Ces plafonds ne réservent pas physiquement des ressources face aux autres sites. La qualification et ses limites sont consignées dans [le relevé du VPS](../../../docs/vps-readiness-2026-09-22.md).

Médias : quota global initial 4 Gio, images d’un magasin 256 Mio, réserve disque 10 Gio. Une vidéo réserve jusqu’à 2 Gio plus sa source avant traitement ; un plafond global de 2 Gio empêcherait toute vidéo. Les fichiers finalisés remplacent ensuite cette réservation par leur taille réelle. Les valeurs doivent être réévaluées avec l’espace disponible et la charge réelle.

Sauvegardes locales `/srv/biobalance-backups`, capacité 4 Gio incluant la copie en cours, réserve opérationnelle 10 Gio. Rétention automatique : jusqu’à 7 copies quotidiennes et 4 hebdomadaires dans ce budget, avec préférence pour deux copies récentes. Les plus anciennes copies valides peuvent être retirées pour faire de la place, sans jamais supprimer la dernière copie valide ; une capacité insuffisante provoque un arrêt explicite. Flux bornés, verrou concurrent, publication atomique et nettoyage des fichiers partiels empêchent l’accumulation de copies échouées. Voir le [runbook](../../../docs/runbook.md).

Les timers `biobalance-backup.timer` et `biobalance-monitor.timer` utilisent `/etc/biobalance/backup.env`. Le moniteur vérifie services, ressources, jobs, fraîcheur et résultat des sauvegardes, copies interrompues/corrompues, santé HTTPS publique et certificat d’origine (>7 jours). Les résultats sont dans journald. Le workflow GitHub de [supervision indépendante](../../../docs/operational-monitoring.md) vérifie HTTPS et le rapport SSH limité, puis envoie les incidents et rétablissements à l’adresse autorisée. La rotation Docker reste plafonnée à 5 fichiers de 10 Mo par service.

Le harnais `tests/deployment/vps-smoke.py` nécessite une invocation explicite avec `--allow-create-media`. Il crée seulement deux petits médias non publiés, réutilise leurs identités lors des reprises, et ne crée ni magasin, ni vente, ni invitation. Il teste MFA, révocation de session, traitement, répétition de transfert, empreintes et plages HTTP. Ses fichiers d’administrateur et d’état restent privés.

Voir [le compte rendu de déploiement](../../../docs/vps-deployment-2026-09-22.md) pour les résultats et limites. Les sauvegardes sur ce VPS ne couvrent pas sa perte totale.
