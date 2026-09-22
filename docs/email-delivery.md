# Emails BioBalance

Les emails concernent uniquement l’accès et la sécurité du compte, conformément à la décision du 22 septembre 2026. Alertes de stock, commandes, livraisons, récompenses et annonces restent dans la boîte de notifications de l’application. Aucun email de vente, marketing, classement ni digest automatique ajouté.

| Message | Déclenchement | Destinataire et contenu |
|---|---|---|
| Invitation responsable | Accès accordé par l’administrateur | Adresse invitée ; organisation, procédure d’activation et code valable 48 heures |
| Invitation équipe | Invitation autorisée dans un magasin | Adresse invitée ; nom du magasin, procédure et code valable 48 heures ; compte existant conservé |
| Récupération | « Mot de passe oublié ? » pour un compte actif | Adresse du compte ; code utilisable une fois pendant 30 minutes |
| Mot de passe modifié | Réinitialisation réussie | Adresse du compte ; date du changement, fermeture des sessions et procédure si le changement est inattendu ; aucun secret |
| Test opérateur | Commande explicite de diagnostic | Adresse explicitement autorisée ; référence de test ; aucun compte créé ou modifié |

## Présentation et confidentialité

Modèles centralisés dans `apps/api/src/shared/email/email-templates.ts` : français, fond blanc, signature BioBalance discrète, texte sombre et colonne de 480 px adaptée aux téléphones. Titres courts, texte courant de 16 px, détails de 14 px, code sur fond blanc avec bordure fine et expiration immédiatement dessous. Aucune barre décorative ni pied de page répété. Les confirmations et tests se limitent à leur information utile ; les instructions d’accès et de sécurité restent explicites. Chaque envoi contient HTML et texte brut. Les noms d’organisation/magasin sont échappés. Aucune image distante, police téléchargée, publicité, pièce jointe ou pixel de suivi. Les dates sont explicites en heure de Tunis, format `JJ/MM/AAAA` et 24 heures ; un message retardé ne promet pas une nouvelle durée de validité.

Le code se copie sans caractères ajoutés. Un seul bouton apparaît si `ACTIVATION_URL` / `RECOVERY_URL` désigne une route HTTPS configurée ; le lien long n’est pas répété dans le HTML. Le code et la procédure manuelle restent disponibles en alternative. Sans association de liens vérifiée, cette procédure est complète. La configuration doit être identique pour les API et le worker.

Aperçu reproductible sans données réelles : `npm run build`, puis `node scripts/preview-emails.cjs`. Le dossier `.artifacts/email-previews/` contient cinq exemples HTML/texte et un sélecteur avec une largeur de téléphone de 320 px. Les codes d’exemple ne donnent aucun accès.

## Envoi et récupération

L’identité crée le jeton et le job dans la même transaction. Les nouvelles charges sont typées/versionnées. Le worker reste compatible avec les anciennes invitations/récupérations texte : conversion en mémoire sans changer le job ni son contenu persistant.

Avant chaque envoi, le worker revalide destinataire, empreinte du code, expiration, consommation, compte actif et autorité actuelle de l’émetteur de l’invitation. Les messages devenus inutilisables sont supprimés de la file avec l’état `completed` et un événement expurgé `email.suppressed`. L’activation applique la même politique d’autorisation. Les changements de droits restent vérifiés à l’utilisation du code, même s’ils arrivent après l’envoi SMTP.

Le worker vérifie également sa possession du job avant l’appel SMTP. Les échecs suivent la reprise bornée du système de jobs ; une reprise utilise le même Message-ID avec le domaine de l’expéditeur. SMTP n’offre pas d’exactement-une-fois : une réponse perdue après acceptation peut provoquer une répétition, même avec le même Message-ID. Les charges contenant des codes sont effacées après réussite ou échec terminal. Les journaux ne contiennent ni code, ni corps, ni adresse destinataire. Une demande de récupération est limitée par IP et par adresse (trois demandes par quinze minutes pour une adresse, même avec plusieurs IP).

La confirmation du changement de mot de passe est ajoutée dans la transaction qui change le mot de passe et révoque les sessions. Une répétition du jeton ne crée pas une seconde confirmation. Les adresses inconnues et les comptes désactivés reçoivent la même réponse de récupération, sans envoi.

SMTP utilise TLS validé (TLS 1.2 minimum), authentification, délais bornés, un destinataire explicite et aucun accès aux fichiers/URLs depuis Nodemailer. `email.smtp_accepted` atteste l’acceptation par le relais SMTP. **Ce résultat ne prouve pas le placement dans la boîte de réception Gmail** : la confirmation du destinataire et, si nécessaire, les en-têtes Gmail déterminent réception, classement spam et SPF/DKIM/DMARC.

## Déploiement et diagnostic

Mettre à jour le worker avant les API : le nouveau worker comprend anciennes et nouvelles charges. Pour revenir à une ancienne API, conserver le nouveau worker jusqu’au traitement des nouvelles charges ; ne pas rétrograder le worker sur une file contenant des messages versionnés. Aucune migration de base n’est nécessaire.

Test réel seulement après autorisation explicite de l’adresse : `node dist/tools/send-email-test.js --to DESTINATAIRE --reference UUID`. Exécuter cette commande dans le conteneur worker. Conserver la même référence lors d’une réponse de commande perdue : un job déjà présent n’est pas réémis. Aucun endpoint public de test SMTP n’existe. Inspecter le statut du job et l’événement `email.smtp_accepted`, puis demander confirmation au destinataire.

Validation automatisée : `npm run test:email`, avec PostgreSQL de test et Mailpit local (`1029` SMTP / `8029` HTTP). Les tests couvrent rendu, échappement, anciens messages, politique d’accès, codes expirés/consommés, destinataire désactivé, perte de lease, reprise, confirmation transactionnelle et réception multipart réelle dans Mailpit. CI lance cette suite avec un service Mailpit isolé.
