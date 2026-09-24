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

- Analyse Flutter initiale sans diagnostic ; vérification finale enregistrée avant compilation.
- 280 tests Flutter réussis. Les quatre tests nécessitant un serveur/laboratoire sont signalés séparément, sans être comptés comme réussis dans cette commande.
- 126 tests backend distincts réussis : règles, transactions, permissions, notifications, emails, médias et neuf tests de suivi des invitations.
- Nouveaux cas : code remplacé/révoqué/utilisé, droits de groupe, reprise idempotente après réponse perdue, versions concurrentes, affectation unique y compris entre groupes, conservation de l’ancien accès après rejet.
- Tests de mise en page : téléphone et paysage 200 %, boutons médias accessibles, clavier, formulaires et 30 écrans du registre visuel.
- Test explicite du retour administrateur bloqué si le brouillon ne peut pas être sauvegardé ; filtres commandes alignés et dernière option atteignable.
- 66 contrats HTTP validés contre le serveur réel, puis décodés et conservés par le transport Dart. Les deux tests HTTP + SQLite + PostgreSQL de reprise passent : cinq opérations, six mouvements, trois révisions, stock 7/1 v7 et 20 points ; lot manquant sans entrée artificielle.
- Build signé, parcours natifs et déploiement : résultats à compléter après exécution.

## Registre visuel

Captures de fixtures contrôlées, sans comptes ni données réelles :

- [Création produit](screenshots/audit-product-editor.png), [contrôle image](screenshots/audit-product-editor-image.png).
- [Produits associés](screenshots/audit-training-association.png), [vidéo](screenshots/audit-training-media.png), [publication](screenshots/audit-training-publication.png).
- [Invitations](screenshots/audit-invitations.png), [affectation vendeur](screenshots/audit-group-invitation.png), [commandes](screenshots/audit-orders.png).

Les captures produit et formation ont été inspectées pour l’alignement, la hiérarchie et les actions. Les images ne constituent pas une qualification physique de tous les parcours.

## Migration et retour arrière

Migration additive 202609240004. Précontrôle de production : aucune affectation multiple de vendeur et aucune invitation active comportant plusieurs magasins lors du contrôle initial. Recontrôler avant déploiement. Les anciennes lignes de codes n’ont pas de date de création inventée. Le backend précédent reste compatible avec les nouvelles colonnes ; la contrainte vendeur continue de s’appliquer après retour arrière.

Avant changement des images : sauvegarde locale vérifiée et copie privée de la configuration courante. Ne pas supprimer les index pour contourner une affectation incompatible. Ne pas restaurer la base en remplacement des données courantes pour un simple rollback applicatif. Les sauvegardes hors VPS restent reportées.

## Limites

La future organisation métier des commandes attend les indications de l’utilisateur. Publication Apple/Google, qualification physique iOS et pilote complet restent hors de cette mise à jour. Aucun effacement de données, aucun email réel de test envoyé.
