# Supervision indépendante

Le contrôle local tourne chaque minute sur le VPS. Le workflow `operations-monitor.yml`, exécuté par GitHub Actions toutes les dix minutes environ, vérifie HTTPS depuis un autre hôte et récupère un rapport technique par SSH. GitHub peut retarder un cron : cette fréquence n’est pas un engagement de disponibilité.

Le compte SSH `biobalance-monitor` ne peut exécuter que le rapport JSON fixe installé sous `/usr/local/lib/biobalance/monitor-report.py`. Sa clé utilise `restrict` et une commande forcée. Aucun shell interactif, tunnel, fichier de configuration, secret ou donnée métier n’est exposé. Le programme et les fichiers SSH appartiennent à root ; sudo autorise uniquement ce programme sans argument. L’empreinte SSH provient de la connexion opérateur existante et sa vérification reste obligatoire.

Le rapport contrôle disque, mémoire, charge, état et fraîcheur du moniteur local, service/timer de sauvegarde et âge de la dernière copie. Le moniteur local couvre aussi conteneurs, jobs, sommes de contrôle et expiration du certificat d’origine. HTTPS est vérifié séparément avec trois tentatives bornées.

Les alertes d’infrastructure sont envoyées au destinataire autorisé, conservé dans le secret `MONITOR_EMAIL_TO`. Elles ne modifient pas la règle métier : stock, commandes et récompenses restent dans l’application. SMTP utilise TLS avec vérification de certificat depuis GitHub, donc une panne du VPS n’empêche pas la tentative d’envoi.

Un changement d’incident déclenche un message, puis au maximum un rappel toutes les six heures tant que l’incident est identique. Le rétablissement exige deux passages sains. Les messages SMTP peuvent être remis en double si une confirmation est perdue ; aucune promesse de livraison exactement une fois n’est faite. L’état sans donnée personnelle est conservé dans un petit artefact GitHub pendant sept jours. Seuls les artefacts de ce workflow sur `main`, déclenchés par cron ou manuellement, sont acceptés. Les clés temporaires du runner sont supprimées, jamais jointes aux artefacts.

## Maintenance

- Secrets du dépôt : `MONITOR_SSH_KEY`, `MONITOR_KNOWN_HOSTS`, `MONITOR_SMTP_USER`, `MONITOR_SMTP_PASSWORD`, `MONITOR_EMAIL_TO`.
- Après changement légitime de clé hôte, vérifier la nouvelle empreinte via un canal administrateur avant de modifier le secret ; ne pas désactiver `StrictHostKeyChecking`.
- `workflow_dispatch`, option `diagnostic=true`, envoie un seul test si aucun incident nouveau n’est détecté. Une acceptation SMTP ne prouve pas la présence dans la boîte principale Gmail.
- En cas de panne SMTP, le workflow échoue sans enregistrer l’incident comme notifié. Les notifications GitHub d’échec constituent un signal complémentaire selon les préférences du propriétaire.
- Les workflows cron d’un dépôt public peuvent être désactivés par GitHub après une longue période sans activité. Contrôler leur exécution dans Actions et les réactiver si nécessaire. Une supervision avec engagement de disponibilité exige un fournisseur dédié.
- Sauvegardes locales : plafond de 4 Gio, réserve de 10 Gio, rotation 7 quotidiennes/4 hebdomadaires, dernière copie valide protégée. Les contrôles ne constituent pas une sauvegarde hors VPS.

Validation locale : tests de transition incident/rappel/rétablissement, lecture SSH forcée et contrôle HTTPS. La validation du runner distant et de l’email est consignée dans le registre d’implémentation après exécution.
