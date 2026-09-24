# Formulaires, invitations et navigation — 24 septembre 2026

Candidate Android 1.1.8+12. Cette mise à jour conserve les données de test et les comptes. Aucun reset prévu.

## Changements

- Formulaire produit : identité, informations/utilisation, prix de référence, vérification/publication ; image et contrôles sur la largeur du formulaire.
- Formation : sections contenu/format/produits/vidéo/publication, boutons médias alignés, aperçu dans le formulaire, un seul bouton fixe d’enregistrement.
- Administration : supervision explicite du groupe, retour direct à la vue globale, arrêt de l’empilement des changements d’onglet. Sauvegarde des brouillons avant changement de contexte.
- Paramètres : coordonnées et accès du groupe regroupés ; suspension/réactivation/archivage conservés ; accès à l’équipe et au suivi des invitations.
- Invitations : états en attente, expirée, acceptée, révoquée, remplacée et retirée ; renvoi avec invalidation de l’ancien code, révocation et retrait de liste. Historique conservé. Les anciens codes consommés sans motif sont « Terminée ».
- Vendeur : un seul magasin actif, imposé par le formulaire, les commandes backend et une contrainte PostgreSQL. Réaffectation dans le groupe atomique ; une affectation dans un autre groupe n’est jamais supprimée implicitement.
- Commandes : filtres sur une ligne défilante. Aucune modification du processus métier des commandes dans cette mise à jour.

## Vérifications locales

- Analyse Flutter finale sans diagnostic ; génération OpenAPI/Dart reproductible et contrôle de dérive réussi.
- 280 tests Flutter réussis. Les quatre tests nécessitant un serveur/laboratoire sont signalés séparément, sans être comptés comme réussis dans cette commande.
- 126 tests backend distincts réussis : règles, transactions, permissions, notifications, emails, médias et neuf tests de suivi des invitations.
- Nouveaux cas : code remplacé/révoqué/utilisé, droits de groupe, reprise idempotente après réponse perdue, versions concurrentes, affectation unique y compris entre groupes, conservation de l’ancien accès après rejet.
- Tests de mise en page : téléphone et paysage 200 %, boutons médias accessibles, clavier, formulaires et 30 écrans du registre visuel.
- Test explicite du retour administrateur bloqué si le brouillon ne peut pas être sauvegardé ; filtres commandes alignés et dernière option atteignable.
- 66 contrats HTTP validés contre le serveur réel, puis décodés et conservés par le transport Dart. Les deux tests HTTP + SQLite + PostgreSQL de reprise passent : cinq opérations, six mouvements, trois révisions, stock 7/1 v7 et 20 points ; lot manquant sans entrée artificielle.
- Deux parcours natifs Android réussis contre API/PostgreSQL isolés, incluant les trois rôles. Après les dernières retouches de mise en page, 78 tests ciblés ont réussi. Les captures et le suivi des invitations ont également été vérifiés.
- Quatre APK et quatre AAB 1.1.8+12 signés : identités, certificats, alignement natif et empreintes vérifiés. Aucun de ces contrôles ne remplace une qualification physique complète.

## Registre visuel

Captures de fixtures contrôlées, sans comptes ni données réelles :

- [Création produit](screenshots/audit-product-editor.png), [contrôle image](screenshots/audit-product-editor-image.png).
- [Produits associés](screenshots/audit-training-association.png), [vidéo](screenshots/audit-training-media.png), [publication](screenshots/audit-training-publication.png).
- [Invitations](screenshots/audit-invitations.png), [affectation vendeur](screenshots/audit-group-invitation.png), [commandes](screenshots/audit-orders.png).

Les captures produit et formation ont été inspectées pour l’alignement, la hiérarchie et les actions. Les images ne constituent pas une qualification physique de tous les parcours.

## Livraison et preuves finales

Code principal `7bac0ce4f8997912349813331d5d0e83629b3ecb`, puis correction backend `1d312cf5032c9596fcaefe1ec94cfc623b980dc0` : une invitation dans un groupe suspendu renvoie `WORKSPACE_INACTIVE` sans faire perdre le contexte administrateur. Les quatre manifestes signés référencent `1d312cf` ; les sources mobiles sont identiques entre ces deux commits.

[CI du code livré](https://github.com/haider0708/bio-balance-app/actions/runs/35990740978) : backend, Android, parcours Android et compilation iOS non signée réussis.

Backend déployé : `biobalance-api:1d312cf` et `biobalance-media:1d312cf`. Quatre API, deux workers, Nginx et PostgreSQL sains ; 24 migrations appliquées. HTTPS `/health` renvoie 200, et le nouvel endpoint invitations sans session renvoie 401.

Comptages avant/après identiques : 5 comptes, 52 produits, 1 groupe, 2 magasins, aucune vente et 1 mouvement de stock. Aucune réinitialisation. Sauvegarde `/srv/biobalance-backups/20260924T105645Z-02408524` restaurée et vérifiée dans une base/médiathèque isolées ; ressources de cet exercice supprimées après contrôle. Configuration précédente conservée dans `/opt/biobalance/rollback-forms-1d312cf/backend.env`, fichier privé non versionné.

Nettoyage limité aux anciennes images BioBalance : conservation des versions `1d312cf`, `7bac0ce` et `505795b`. Environ 4 Go libérés ; 27 Go disponibles après nettoyage. Les timers sauvegarde, surveillance et TLS restent actifs. Aucun service des autres sites modifié.

### Paquets Android

| Application | Identifiant | APK SHA-256 |
|---|---|---|
| admin | `tn.biobalance.app` | `daf697cfe6e20b51fe26d1e86b1e6cc8eff99197b1aabc564eebf1d935232fa0` |
| responsable | `tn.biobalance.app.responsable` | `fd110b0b87ae62f84e8e89f55613450c07cf593a532d09e394e47b7723639117` |
| vendeur | `tn.biobalance.app.vendeur` | `a789d06dd0b19db8a0a99240c9e726bfc6c6333f5079bc3f7d92696ea457c615` |
| vendeur2 | `tn.biobalance.app.vendeur2` | `d89293a5c4d9ff8588e4d1ebb333c644919aecd6ddf8c3cbbcdf56e2ced85695` |

Les fichiers signés et leurs manifestes sont conservés localement ; le registre `.artifacts/forms-release/verified-artifacts.json` contient chemins et empreintes APK/AAB. La première tentative Responsable a subi un crash du compilateur JIT C2 du JDK hôte. La reprise avec `JAVA_TOOL_OPTIONS=-XX:-UseLoopPredicate` a réussi ; cet ajustement concerne uniquement la JVM de compilation. Les optimisations et contrôles de signature de l’application sont conservés.

### Installation Samsung — réalisée

Le 24 septembre 2026, après une tentative USB interrompue par la déconnexion du câble, la connexion sans fil a été rétablie et l’identité du Samsung SM-G975F a été vérifiée. Les quatre applications Admin, Responsable, Vendeur et Vendeur 2 ont été mises à jour en place vers **1.1.8+12** avec `adb install -r --no-incremental`. Chaque installation a réussi ; les UID 10358, 10359, 10360 et 10361 sont inchangés. Aucune désinstallation, aucun effacement de données et aucune réinitialisation du backend.

Pour chaque application : version vérifiée, processus vivant, activité au premier plan et absence d’exception fatale/non gérée observée dans les journaux du processus lors du contrôle de démarrage. Admin est laissé ouvert. Les preuves locales sont `installed-{role}.json` et `phone-startup-checks.json` dans `.artifacts/forms-release/`. Ce contrôle confirme installation et ouverture ; le parcours tactile complet des nouveaux formulaires sur Samsung reste à valider avec l’utilisateur.

Les preuves locales sont sous `.artifacts/forms-*` et `.artifacts/forms-release/` : tests, contrats, CI, sauvegarde/restauration, migrations, déploiement, images, services et manifestes. Les fichiers contenant une configuration privée ne sont jamais joints au dépôt.

## Migration et retour arrière

Migration additive 202609240004. Précontrôle de production : aucune affectation multiple de vendeur et aucune invitation active comportant plusieurs magasins lors du contrôle initial. Ce précontrôle a été répété et réussi avant les deux déploiements. Les anciennes lignes de codes n’ont pas de date de création inventée. Le backend précédent reste compatible avec les nouvelles colonnes ; la contrainte vendeur continue de s’appliquer après retour arrière.

Avant changement des images : sauvegarde locale vérifiée et copie privée de la configuration courante. Ne pas supprimer les index pour contourner une affectation incompatible. Ne pas restaurer la base en remplacement des données courantes pour un simple rollback applicatif. Les sauvegardes hors VPS restent reportées.

## Limites

La future organisation métier des commandes attend les indications de l’utilisateur. Publication Apple/Google, qualification physique iOS et pilote complet restent hors de cette mise à jour. Aucun effacement de données, aucun email réel de test envoyé.
