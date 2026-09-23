# BioBalance — synchronisation entre magasins et paramètres

## Défaut reproduit

Sur le Samsung, le magasin « DÉMO — DAS PARA Sahloul » affichait « Synchronisation · 1 en attente », alors que sa page de synchronisation affichait « Tout est synchronisé ». Le compteur portait sur tous les magasins du compte, mais la liste et l’envoi ne concernaient que le magasin ouvert. Au niveau réseau/groupe, aucun magasin actif ne permettait de traiter la file.

## Correction

- La page Synchronisation présente les opérations de ce compte sur ce téléphone, avec leur groupe, magasin et date. Les magasins inaccessibles sont signalés et leurs opérations conservées.
- Le compteur suit les changements SQLite, même quand le nombre reste identique et qu’une opération passe en erreur. Les libellés distinguent envoi, nouvelle tentative programmée, dépendance bloquée, conflit et confirmation en cours d’application.
- La synchronisation fonctionne depuis le réseau, un groupe ou un magasin, sans changer l’espace affiché. Un passage traite au maximum huit magasins et cinquante commandes par magasin. Les passages suivants alternent les magasins en attente.
- Les appels simultanés attendent le même travail réel. Changer de magasin pendant un passage déclenche ensuite le chargement du magasin choisi, sans attendre le prochain cycle.
- Les installations de snapshots d’un même compte/session/magasin sont sérialisées. Une ancienne réponse ne peut plus remplacer un snapshot demandé après elle.
- Les réponses de confirmation invalides restent incertaines et récupérables. Les identifiants, payloads, dépendances et délais de reprise restent persistés. Une réponse perdue est vérifiée ; les effets provisoires ne sont retirés qu’avec l’état serveur confirmé.
- Les erreurs réseau, de session et d’accès restent distinctes des conflits métier. Une panne ne déclenche pas une boucle rapide d’envoi. Une session expirée arrête les tentatives automatiques jusqu’à reconnexion.
- Les raccourcis redondants « Choisir un magasin », « Magasins du groupe » et « Groupes partenaires » sont retirés des paramètres. Les réglages du magasin et du groupe, équipes, prix, points, seuils, historique et compte restent disponibles. La navigation conserve le sélecteur de groupe dans l’en-tête et la liste de magasins dans le groupe.

Aucune migration, aucune modification des règles de stock/points et aucun effacement de données ou d’opérations. Le backend existant reste compatible.

## Vérifications et livraison

Analyse Flutter sans diagnostic. Suite complète : **252 tests réussis**, quatre scénarios nécessitant des fixtures restent omis par cette commande. Treize régressions supplémentaires couvrent magasins masqués, envoi depuis le réseau, appels simultanés, onze magasins traités par passages bornés, ordre des snapshots, réponses perdues/invalides, isolation des comptes, états en direct et texte à 200 %.

Le parcours HTTP réel Flutter/SQLite/NestJS/PostgreSQL réussit : cinq commandes, six mouvements, trois révisions, stock vendable 7 / endommagé 1, version de lot 7 et solde de 20 points. Le scénario de vente avec lot manquant réussit également, sans entrée de stock artificielle. Ces données sont exclusivement synthétiques et isolées de la production.

Les résultats exécutés et l’identifiant de la candidate sont consignés dans la preuve de livraison associée. Les journaux détaillés restent dans `.artifacts/sync-*.log`. Les captures de test utilisent des données synthétiques ; le constat initial Samsung est conservé dans `.artifacts/sync-phone-operation.xml`.

La synchronisation automatique en arrière-plan demeure soumise aux limites du système mobile. La reprise fiable s’effectue lorsque l’application est ouverte et connectée. Un conflit métier exige une vérification explicite ; il ne doit pas être effacé pour faire disparaître le compteur.

La reprise native Android réussit après arrêt forcé : identité et payload inchangés, une seule vente acceptée, stock 7 / version 3 et 30 points. Le même scénario vérifie le refus caméra, sa solution de recherche manuelle et la vidéo H.264 téléchargée lue sans réseau. Ce scénario émulateur ne constitue pas une mesure de performance physique.
