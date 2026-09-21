# État de l’implémentation — 21 septembre 2026

L’application est en développement et n’est pas encore qualifiée pour une diffusion en production. Ce document distingue les fonctionnalités codées des vérifications réalisées.

## Fonctionnalités présentes

- Flutter Android/iOS, français, thème BioBalance et Inter local, navigation par rôle, sélection de magasin, formulaires et états d’erreur.
- Identité email/mot de passe, invitations, récupération, sessions révocables, MFA TOTP administrateur et provisionnement privé.
- Organisations, magasins, équipes, catalogue, import CSV avec validation préalable et configuration des prix/seuils/points.
- Stock par lot/péremption, réceptions, ventes, corrections, retours, dommages, ajustements, alertes de stock et de péremption.
- Transactions PostgreSQL avec contraintes, RLS, versions, idempotence, journaux de stock/points/audit et protection des historiques.
- Commandes et livraisons partagées, réception unique, suivi des quantités réellement reçues et des reliquats.
- Points à la première synchronisation acceptée, réservations, remise de récompenses et débit produit, soldes négatifs et classement mensuel.
- SQLite avec outbox durable, brouillons, reprise après arrêt, isolation compte/magasin, résolution des saisies rejetées et migration avec file peuplée.
- Synchronisation différentielle des lots/configurations ; collections autorisées actualisées et rechargement complet si catalogue modifié ou backlog important.
- Articles/vidéos, téléversement par fragments, traitement média, publication contrôlée, cache de formation et téléchargement vidéo.
- Annonces du responsable, notifications opérationnelles, enregistrement push lié à une session valide, historique consultable dans l’application.
- Vue administrateur, historiques paginés de ventes/points/audit/mouvements et export des lignes affichées.
- Docker Compose VPS, deux API, workers séparés, Nginx, migrations, sauvegarde locale, restauration isolée, CI et scénario k6.

## Vérifications réalisées localement

| Vérification | Résultat constaté |
|---|---|
| Compilation TypeScript | Réussie |
| Tests domaine backend | 6 réussis |
| Tests PostgreSQL réels avec rôle restreint | 12 réussis |
| Tests Flutter de reprise, migration et dispositions d’écran | 13 réussis |
| Build Android debug | APK produit ; les dernières modifications doivent encore être vérifiées sur l’application exécutée |
| Sauvegarde/restauration isolée | Réussie sur les données de développement ; archive média vide, à compléter avec des médias réels traités |
| OpenAPI et génération Dart | Exécutés, 38 méthodes de transport générées |
| Images Docker et émulateur | Vérifications commencées ; résultat final à confirmer |

Un passage des tests PostgreSQL a expiré pendant une forte saturation mémoire de l’hôte par les builds Android. Après arrêt des anciens daemons de compilation devenus inutiles, les 12 tests ont réussi sans allonger leur délai.

## Travail restant avant acceptation

- Terminer la vérification des images conteneur, de l’application exécutée et de la restauration avec des médias non vides.
- Compléter les parcours UI automatisés des trois rôles ; vérifier les permissions retirées pendant qu’un écran secondaire est ouvert, les erreurs de stockage, le téléchargement interrompu et les reprises de téléversement sur téléphone.
- Compléter les détails UX restants : restauration automatique de certains brouillons de formation/annonce, association produit dans l’éditeur de formation, préférences/images facultatives, réception entièrement manquante et commande préremplie depuis une alerte.
- Vérifier les versions provisoires des lots lors d’enchaînements de plusieurs opérations hors ligne, et enrichir les tests de fusion différentielle et de résolution de dépendances.
- Compléter les schémas de requête/réponse OpenAPI encore génériques et la couverture des contrats.
- Exécuter tests caméra/push, accessibilité, rotation et stabilité mémoire sur Android/iOS physiques ; compiler iOS sur macOS et produire les builds signés.
- Préparer les données de charge représentatives, exécuter 100 req/s et le pic 200 req/s sur le VPS de référence ; mesurer réellement démarrage, recherche, persistance et fluidité. Aucune de ces performances n’est encore revendiquée.
- Renseigner VPS/domaine/SMTP/Firebase/APNs/signatures, valider renouvellement TLS/supervision, puis effectuer le pilote et corriger ses retours.

Les sauvegardes hors VPS, la haute disponibilité, les abonnements payants, l’admin web, WhatsApp et les classements hors magasin restent reportés conformément au périmètre approuvé.
