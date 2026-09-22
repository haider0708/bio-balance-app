# Conditions de diffusion

Ce registre distingue l’implémentation, les preuves locales et l’acceptation réelle. Une case en attente ne devient jamais réussie par la seule compilation. Les références de commits sont dans `implementation-status.md`.

| Porte de sortie | Vérifications réalisées | Validation restante |
|---|---|---|
| Métier / isolation / historique | Tests domaine, PostgreSQL restreint, contrats, synchronisation et parcours Android réussis | Recette signée avec données pilotes |
| Accès / pannes / reprise | Révocation en cours de saisie, réponses perdues, force-stop et saturation SQLite testés | Appareils Android/iOS réels et lecteurs d’écran |
| Images / vidéo / transfert | Traitement réel, HTTPS Nginx/Cloudflare sur VPS, checksum/plages, lecture hors ligne Android locale | iOS et connexions mobiles réelles |
| Notifications | Audiences, sessions, doublons, workers et boîte interne vérifiés ; SMTP réel authentifié en TLS | Réception réelle des emails ; alertes OS app fermée reportées, sans Firebase |
| Performance API | 100 req/s + pic 200 req/s réussis sur l’hôte local ; données 500 magasins/5 000 comptes/>2 M ventes | Rejouer derrière TLS/Nginx/workers sur le VPS cible |
| Performance mobile | SQLite VM mesurée ; interface vérifiée sur émulateur | Android 4 Go : p95 démarrage ≤2,5 s, vente ≤250 ms, recherche ≤150 ms, images manquées <1 % ; iOS/caméra/mémoire |
| Déploiement / reprise | VPS go2code installé, Cloudflare/HTTPS réel, 13 migrations, RLS, médias protégés, timers et restauration non vide ; rollback local vérifié | Charge du VPS partagé, maintenance SSH/hôte coordonnée et supervision/alertes indépendantes |
| CI | Dépôt GitHub publié ; backend et compilation iOS macOS réussis pour le commit v1.0.0 | Vérifier la fin des jobs Android du [pipeline du commit de release](https://github.com/haider0708/bio-balance-app/actions/runs/35738028697) et traiter les échecs éventuels |
| Android | APK v1.0.0+2 signé avec la clé d’application et AAB avec la clé d’upload ; API réelle, signature, ZIP/ELF 16 Kio, installation et écran de connexion sur émulateur vérifiés | Sauvegarde chiffrée indépendante des clés, inscription Play, upgrades entre canaux, Play Internal Testing et téléphones physiques |
| iOS | Configuration, entitlements et compilation release non signée réussie sur macOS via GitHub Actions | Équipe/profil/certificat Apple, archive signée, TestFlight et validation physique |
| Pilote | Plan, recette et registre d’incidents préparés | 5 magasins, ≥14 jours, les 3 rôles et les 2 plateformes |

Aucun élargissement à 50 magasins avant fermeture des défauts critiques de sécurité, intégrité ou parcours essentiels et réussite des portes applicables. Le pilote exige déjà une version signée et un environnement contrôlé ; il ne remplace pas les vérifications bloquantes ci-dessus.

## Dossier de preuve à renseigner

Pour chaque validation : date UTC, version/commit et SHA-256 de l’artefact, environnement/appareil/OS, données utilisées, commande/scénario, résultat, journaux expurgés, personne responsable et lien d’incident si échec. Conserver les résultats échoués ; une correction exige le nouveau résultat et le test de non-régression concerné.

Les fichiers sous `.artifacts/deployment-lab/`, les tokens de charge, certificats privés et fichiers de signature ne font pas partie du dossier public. Les sorties résumées versionnées sont distribuables ; les logs bruts doivent être vérifiés avant partage.

Attestation Play Integrity/App Attest et pinning ne sont pas actifs. Les [limites de la protection](security-hardening.md) doivent rester explicites ; aucun indicateur client ne remplace l’autorisation serveur.
