# Conditions de diffusion

Ce registre distingue l’implémentation, les preuves locales et l’acceptation réelle. Une case en attente ne devient jamais réussie par la seule compilation. Les références de commits sont dans `implementation-status.md`.

| Porte de sortie | Vérifications réalisées | Validation restante |
|---|---|---|
| Métier / isolation / historique | Tests domaine, PostgreSQL restreint, contrats, synchronisation et parcours Android réussis | Recette signée avec données pilotes |
| Accès / pannes / reprise | Révocation en cours de saisie, réponses perdues, force-stop et saturation SQLite testés | Appareils Android/iOS réels et lecteurs d’écran |
| Images / vidéo / transfert | Traitement réel, HTTPS Nginx/Cloudflare sur VPS, checksum/plages, lecture hors ligne Android locale | iOS et connexions mobiles réelles |
| Notifications | Audiences, sessions, doublons, workers et boîte interne vérifiés ; modèles d’accès/sécurité testés et déployés ; réception Gmail confirmée dans Spam, SPF/DKIM/DMARC PASS | Surveiller le classement Gmail ; alertes OS app fermée reportées, sans Firebase |
| Performance API | 100 req/s + pic 200 req/s réussis sur le VPS cible avec TLS/Nginx/4 API/workers et client externe ; 500 magasins/5 000 comptes/>2 M ventes ; aucun rejet ni itération perdue | Reconnexions simultanées massives non qualifiées ; surveiller la contention du VPS partagé pendant le pilote |
| Performance mobile | SQLite VM mesurée ; interface vérifiée sur émulateur | Android 4 Go : p95 démarrage ≤2,5 s, vente ≤250 ms, recherche ≤150 ms, images manquées <1 % ; iOS/caméra/mémoire |
| Déploiement / reprise | VPS go2code installé, Cloudflare/HTTPS réel, RLS, médias protégés, renouvellement ACME dédié, supervision externe et restauration finale de 53 médias/17 tables métier ; rollback sur la base VPS isolée avec 14 migrations vérifié ; 8 services sains, charge qualifiée | Maintenance globale et MySQL des autres sites exclus par le propriétaire ; validation physique/pilote toujours requise |
| CI | Les quatre jobs backend, Android, parcours Android/reprise et compilation iOS non signée réussissent sur `3be5389` ; [exécution complète](https://github.com/haider0708/bio-balance-app/actions/runs/35784854922) | Aucune pour ce commit ; conserver ces contrôles pour les changements suivants |
| Android | APK v1.0.0+2 signé avec la clé d’application et AAB avec la clé d’upload ; API réelle, signature, ZIP/ELF 16 Kio, installation et écran de connexion sur émulateur vérifiés | Archive chiffrée vérifiée : copie indépendante par le propriétaire encore requise ; inscription Play, upgrades entre canaux, Play Internal Testing et téléphones physiques |
| iOS | Configuration, entitlements et compilation release non signée réussie sur macOS via GitHub Actions | Équipe/profil/certificat Apple, archive signée, TestFlight et validation physique |
| Pilote | Plan, recette et registre d’incidents préparés | 5 magasins, ≥14 jours, les 3 rôles et les 2 plateformes |

Aucun élargissement à 50 magasins avant fermeture des défauts critiques de sécurité, intégrité ou parcours essentiels et réussite des portes applicables. Le pilote exige déjà une version signée et un environnement contrôlé ; il ne remplace pas les vérifications bloquantes ci-dessus.

## Dossier de preuve à renseigner

Pour chaque validation : date UTC, version/commit et SHA-256 de l’artefact, environnement/appareil/OS, données utilisées, commande/scénario, résultat, journaux expurgés, personne responsable et lien d’incident si échec. Conserver les résultats échoués ; une correction exige le nouveau résultat et le test de non-régression concerné.

Les fichiers sous `.artifacts/deployment-lab/`, les tokens de charge, certificats privés et fichiers de signature ne font pas partie du dossier public. Les sorties résumées versionnées sont distribuables ; les logs bruts doivent être vérifiés avant partage.

Attestation Play Integrity/App Attest et pinning ne sont pas actifs. Les [limites de la protection](security-hardening.md) doivent rester explicites ; aucun indicateur client ne remplace l’autorisation serveur.

Le [relevé d’exploitation et du catalogue](vps-readiness-2026-09-22.md) complète ce registre. Les cinq magasins de démonstration, sept tarifs fictifs et douze EAN absents ne constituent pas une validation des données commerciales réelles. Les sauvegardes locales ne couvrent pas la perte du VPS.
