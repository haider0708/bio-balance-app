# Essai manuel sur un seul téléphone

Trois installations privées partagent le même backend HTTPS et le même code :

| Application | Identifiant Android | Compte à utiliser |
|---|---|---|
| BioBalance Admin | `tn.biobalance.app` | Administrateur existant |
| BioBalance Responsable | `tn.biobalance.app.responsable` | Responsable invité par l’admin |
| BioBalance Vendeur | `tn.biobalance.app.vendeur` | Vendeur invité par le responsable |

Ces libellés facilitent le test ; ils ne donnent aucun droit. Les autorisations viennent toujours du compte et des appartenances validées par le serveur. Chaque installation possède sa propre session, SQLite, cache, brouillons et file de synchronisation. L’APK Admin met à jour l’application existante avec la même signature. Les autres APK s’installent à côté. Ils ne sont pas destinés à trois publications Play Store.

Pour éviter que les installations se disputent les liens de compte, les copies Responsable/Vendeur utilisent « Activer mon invitation » et la saisie du code reçu par email. La copie principale conserve les liens vérifiés lorsqu’ils sont configurés.

## Construire

Depuis un commit propre, avec les clés privées existantes hors dépôt :

```sh
python3 scripts/build-signed-android.py config/mobile/manual-admin.json /chemin/prive/signing
python3 scripts/build-signed-android.py config/mobile/manual-responsable.json /chemin/prive/signing
python3 scripts/build-signed-android.py config/mobile/manual-vendeur.json /chemin/prive/signing
```

Exécuter ces commandes séquentiellement. Le script vérifie chaque package, signature et alignement natif. Aucun compte, mot de passe ou privilège n’est incorporé dans les APK.

## Parcours

1. Se connecter dans **Admin** avec le compte existant, son mot de passe et son code MFA.
2. Inviter un responsable. Pour un test personnel, une adresse Gmail avec suffixe `+responsable` permet de recevoir l’invitation dans la même boîte tout en créant un compte distinct.
3. Dans **Responsable**, activer cette invitation, choisir son mot de passe, créer le groupe puis le premier magasin et inviter un vendeur (par exemple avec un suffixe `+vendeur`).
4. Dans **Vendeur**, activer cette seconde invitation et se connecter. Créer les opérations depuis l’interface et les vérifier dans les deux autres applications.

Aucun groupe, stock, lot, vente ou compte d’équipe n’est précréé. Les références produit sans code-barres et les tarifs de démonstration restent identifiés dans le catalogue.

## Réinitialisation de données de test

`scripts/reset-business-keep-catalog.sql` est une procédure de maintenance destructive, hors API. Elle exige une sauvegarde vérifiée, un administrateur existant, le nombre attendu de produits et une confirmation explicite. Répéter d’abord sur une restauration isolée ; arrêter seulement les API/workers BioBalance pendant le reset réel.

Elle conserve exactement les produits, leurs médias, le compte administrateur (mot de passe/MFA inclus), les migrations et un nouvel événement d’audit de maintenance. Elle supprime les groupes, équipes, opérations, formations, invitations, sessions et autres données de test. La liste de tables est explicite, sans `CASCADE`, sans désactiver les triggers ni modifier les droits de la base.

Révoquer les anciennes sessions fait partie du reset. Effacer également les données locales des installations de test concernées avant reconnexion pour éviter les anciennes files hors ligne. Cette suppression locale appartient uniquement à cette réinitialisation demandée ; elle n’est jamais exécutée automatiquement au lancement ou à la mise à jour de l’app.

Vérifier et nettoyer uniquement les fichiers média/export devenus orphelins dans les volumes BioBalance. Conserver la sauvegarde dans la politique existante de rétention (7 jours, 4 semaines, plafond 4 Gio). Les sauvegardes locales ne couvrent pas la perte du VPS.
