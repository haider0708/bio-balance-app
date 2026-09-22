# Déploiement BioBalance — go2code, 22 septembre 2026

Le backend est accessible sur **https://api.galylio.com**. Le contrôle public `GET /health` renvoie `{"status":"ok"}`. Il s’agit d’une API mobile, pas d’un site d’administration web.

## Domaine et architecture installée

Le domaine initial `api.biobalance.com.tn` n’était pas encore délégué publiquement. À la demande de l’utilisateur, l’installation utilise `api.galylio.com` : enregistrement Cloudflare **A**, nom **api**, origine **146.59.195.61**, proxy activé et TTL automatique. L’utilisateur a confirmé **Full (strict)**.

Le VPS `go2code` possède 8 vCPU, environ 16 Go de RAM et 155 Go de disque sous Ubuntu 22.04 LTS. Apache y héberge déjà d’autres applications. Leurs sites/services sont conservés ; BioBalance dispose de son propre hôte virtuel, de son réseau Docker, de sa base et de ses volumes.

```text
Flutter → Cloudflare HTTPS → Apache HTTPS → Nginx (127.0.0.1:18081)
                                              ├─ API 1 / API 2
                                              ├─ médias privés
                                              └─ PostgreSQL + workers
```

Apache accepte l’accès HTTPS à cet hôte uniquement depuis les plages officielles Cloudflare et le loopback. Les en-têtes client sont reconstruits à partir de l’adresse vérifiée ; Nginx ne fait confiance qu’à la passerelle de son réseau. Le contournement par l’IP d’origine est refusé, y compris avec des en-têtes Cloudflare falsifiés. Les autres hôtes virtuels ne sont pas soumis à cette nouvelle restriction.

Le certificat Let's Encrypt pour `api.galylio.com` expire le **21 décembre 2026**. Le timer Certbot existant et le hook dédié assurent son renouvellement et le rechargement gracieux d’Apache. Les challenges ACME restent accessibles en HTTP ; les autres requêtes HTTP sont redirigées vers HTTPS. Les détails de configuration sont dans [shared-vps](../infrastructure/production/shared-vps/README.md).

## Services, données et accès

- Deux API, un worker opérationnel, un worker média limité à un traitement, Nginx et PostgreSQL 17.7 : tous sains lors de la recette.
- Treize migrations appliquées. Les API utilisent `biobalance_app`, sans privilège superuser ni contournement RLS. Le propriétaire de migration n’est pas transmis aux services applicatifs.
- Les 19 tables déclarées `FORCE ROW LEVEL SECURITY` par les migrations sont vérifiées. Les tables de répertoire magasin/adhésion utilisent l’autorisation des transactions serveur ; elles ne sont pas présentées comme protégées par RLS.
- Aucun port PostgreSQL/API publié sur Internet. Seul Nginx publie un port loopback, derrière Apache.
- Volumes persistants `biobalance_database` et `biobalance_media`. L’API autorise les médias avant leur service interne par Nginx ; téléchargements par plages et empreintes vérifiés.
- Administrateur `biobalance@galylio.com` créé avec mot de passe aléatoire et MFA TOTP. Le fichier privé `/etc/biobalance/admin/initial-admin.json` et sa copie locale ignorée par Git contiennent l’accès initial. Ne pas les placer dans les notes publiques ou les logs.
- SMTP `mail.galylio.com:465`, TLS direct, authentification et identité d’envoi `BioBalance <biobalance@galylio.com>` configurés. TLS, authentification et commande NOOP réussis ; aucun message de test envoyé. La réception effective d’une invitation en boîte mail reste à vérifier lors de son premier envoi autorisé.
- Aucun compte partenaire, magasin, vente ou invitation factice créé. Deux petits médias techniques PNG/H.264 non publiés sont conservés pour la vérification ; leurs identifiants sont dans l’état privé de qualification.
- Invitations/récupération par code manuel conservées. Les associations de liens mobiles ne sont pas activées implicitement sur ce domaine temporaire. Firebase reste absent.

Les images applicatives portent le tag `cb0d68d3` et proviennent du code audité. Les stores d’images Docker local/distant exposent des identifiants différents ; chaque couche de système de fichiers, configuration runtime, OS et architecture a été comparé et trouvé identique avant exploitation. Les empreintes sont consignées dans les preuves.

## Recette sur le VPS

- HTTPS public via Cloudflare, certificat d’origine reconnu, `/health`, refus des endpoints protégés sans connexion et absence de Swagger public.
- Simulation Certbot de renouvellement réussie. Le hook dédié a été invoqué séparément : configuration Apache valide et rechargement gracieux réussi.
- Connexion MFA réelle, identité administrateur, déconnexion puis rejet du token révoqué.
- PNG et H.264 traités par le worker, reprise du même transfert, données finales et SHA-256 identiques, requêtes `Range` correctes.
- En-tête `X-Forwarded-For` falsifié ignoré, adresse réelle du client conservée, accès direct à l’origine refusé. Le client Flutter/Dart est accepté.
- Le contrôle d’intégrité Cloudflare refuse le client Python générique (1010). Le harnais utilise son véritable User-Agent `BioBalance-Deployment/1.0` ; aucun filtre Cloudflare n’a été désactivé pour faire passer le test.
- Sauvegarde PostgreSQL/médias restaurée dans une base séparée ; les deux fichiers traités correspondent à leur taille et SHA-256. La base métier reste initiale, avec zéro magasin, vente et mouvement.
- Entrée standard des commandes Docker de sauvegarde corrigée : les scripts ne consomment plus les commandes suivantes d’un shell SSH. Régression sauvegarde puis restauration réussie sans redirection ajoutée par l’appelant ; 14 tests Python de release réussis.

Les résultats détaillés, y compris la recette de renouvellement, sont dans [les preuves versionnées](../tests/deployment/vps-evidence-2026-09-22.json). Les logs, états de qualification et credentials restent privés sous `.artifacts/vps-deployment-2026-09-22/`.

## Exploitation et limites

Configuration root privée : `/etc/biobalance/backend.env`. Commande de service : `sudo biobalance-compose …`. Scripts et configuration : `/opt/biobalance`. Sauvegardes : `/srv/biobalance-backups`.

`biobalance-backup.timer` exécute une sauvegarde chaque nuit vers 02 h 30 UTC. `biobalance-monitor.timer` vérifie chaque minute services, ressources, jobs, fraîcheur des sauvegardes, endpoint HTTPS public et validité du certificat (>7 jours). Les résultats/échecs sont accessibles dans journald. Une supervision indépendante avec acheminement d’alertes reste à raccorder ; un moniteur sur le VPS ne détecte pas lui-même sa disparition.

L’hôte partagé dispose d’environ **29 Go libres, 82 % occupés** à la fin de l’installation. Quotas initiaux : médias 4 Gio au total, images par magasin 256 Mio, sauvegardes 4 Gio, réserve disque 10 Gio. Les vidéos réservent jusqu’à 2 Gio plus leur source avant traitement ; le premier réglage à 2 Gio a été corrigé avant la recette finale. Aucune ancienne sauvegarde ou donnée d’un autre service n’a été supprimée.

Le moniteur alerte à 85 % d’utilisation disque. Étendre/libérer de façon contrôlée le stockage et qualifier la charge du VPS complet avant une grande diffusion. Les limites mémoire/CPU protègent la cohabitation ; elles ne prouvent pas la capacité de 500 magasins. Le redémarrage système déjà demandé par Ubuntu et le durcissement global des accès aux autres applications relèvent d’une maintenance coordonnée de l’hôte, qui n’a pas été imposée pendant cette installation.

Le fichier mobile local `config/mobile/production.local.json` pointe maintenant vers cette API et passe la validation Android/iOS. Les applications signées doivent être reconstruites avec cette configuration avant le pilote. CI distante/macOS, mesures physiques et pilote restent soumis aux [conditions de diffusion](release-gates.md). Sauvegardes hors serveur et haute disponibilité restent reportées ; la restauration locale ne couvre pas la perte complète du VPS.
