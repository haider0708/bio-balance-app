# Revue du code, fiabilité et finition — 22 septembre 2026

Cette passe examine le backend, les données locales, les écrans des trois rôles, les contrats, les harnais de test et la livraison. Elle conserve Flutter/Provider/MVVM, les transactions PostgreSQL, les historiques et les anciennes opérations en attente. Aucune migration métier n’est nécessaire.

## Corrections et simplifications

| Constat | Correction et preuve |
|---|---|
| Navigation continuée après un échec de déconnexion ; ancienne déconnexion pouvant effacer une nouvelle session | Résultat explicite de déconnexion, attente des brouillons, contrôle de génération avant suppression locale et navigation conditionnelle. Tests échec de stockage et connexion concurrente. |
| Écriture SQLite pour chaque frappe ; restauration échouée pouvant être suivie d’une sauvegarde vide | Regroupement des écritures intermédiaires, conservation de la dernière révision et verrouillage des éditeurs jusqu’à récupération. Un flush de cycle de vie ne remplace jamais un brouillon illisible. |
| Répétition rapide d’une demande de récompense | Une commande en vol par compte/magasin/cible ; identifiant durable conservé sur réponse incertaine ; boutons et confirmations protégés. |
| Nettoyage local échoué présenté comme un échec après acceptation | Une annonce, commande ou formation acceptée reste terminée même si son brouillon ne peut pas être effacé. |
| Classement vide après une erreur réseau ou périmé après synchronisation | Modèle et état typés, erreurs visibles, rafraîchissement après synchronisation et conservation du dernier résultat. |
| Liste de synchronisation non actualisée ; construction de toutes les lignes | Écoute des changements de magasin/synchronisation, future réutilisé et liste paresseuse. Test avec 500 opérations. |
| Requêtes d’historique/formation répétées ; HTML reparsé à chaque recherche | Protection des chargements simultanés et index textuel de formation recalculé uniquement quand le contenu change. |
| Manifeste de release auto-déclaré accepté comme preuve de signature | Le package exige le commit et l’empreinte de l’arbre propre, revalide les signatures APK/AAB ou IPA et vérifie à nouveau les fichiers copiés. Publication atomique de l’archive ; compilation seule explicitement non diffusable. |
| Connexion propriétaire des tests insuffisamment contrainte | Validation centralisée des deux URL avant connexion : protocole PostgreSQL, base `_test`, même hôte/port/base, refus des substitutions par paramètres. Les erreurs ne révèlent pas les URL. |
| Chaîne de compilation nécessitant des garde-fous supplémentaires | Hooks npm désactivés par défaut, politique versionnée stricte sous npm 11.19, reconstruction explicite des quatre dépendances approuvées, refus des hooks Scarf/fsevents ; checksum officiel Gradle 9.3.1. |
| Clients des harnais réseau moins stricts que le transport de diffusion | Origines HTTPS ou fixtures locales/émulateur uniquement ; aucune redirection portant les credentials. |
| Dépendances et imports inutilisés | Retrait direct d’`intl` (reste transitif via la localisation Flutter), retrait d’`url_launcher` et de ses sept plugins de plateforme, suppression de deux barrels redondants et d’`API_PUBLIC_URL` inutilisé. README mobile remplacé. |

Les migrations, générateurs, harnais natifs, polices/licences, assets de marque et preuves historiques restent nécessaires. Ils ne sont pas supprimés simplement parce qu’ils ne sont pas importés par `main.dart`.

## Interface

Surfaces blanches, texte anthracite, vert BioBalance pour les actions avec texte sombre contrasté. Petits repères violets pour les cadeaux/formations, bleus pour les livraisons et ambre pour les alertes. Les statuts conservent texte et icône.

Transition d’entrée de 180 ms, sans ancienne page conservée ni effet lourd ; désactivée lorsque l’utilisateur demande moins d’animations. Les listes restent paresseuses et les champs conservent leurs valeurs. Les mesures s’adaptent au texte et évitent de couper un montant TND sur deux lignes. Les tests couvrent les écrans étroits, paysage, clavier, texte à 200 %, cibles accessibles et mouvement réduit.

Captures issues des vrais widgets, vérifiées visuellement : [responsable](screenshots/manager-home.png), [vendeur](screenshots/salesperson-home.png), [administration](screenshots/admin-home.png), [paramètres produits](screenshots/manager-product-settings.png).

## Sécurité et limites de l’examen

Scan statique `192cee76-90d7-4fcb-a227-0af917713478`, source initiale `85b82996eb4cfab843dbfa13bc531c950c93a456`. Revue indépendante et investigations ciblées sur identité, isolation/RLS, stock/points, synchronisation, médias, jobs, UI et outils de livraison. Un constat de faible sévérité concerne la provenance des artefacts ; il est corrigé dans cette passe. Aucun contournement exploitable d’authentification ou d’isolation de magasin n’a été établi.

La saisie de ventes historiques et leur péremption à la date enregistrée restent conformes à la règle métier approuvée. L’absence d’hôte de lien HTTPS reste volontaire : les emails fournissent les codes manuels. Les générateurs et contrôles structuraux ont été examinés ; chaque ligne du code généré et chaque dépendance tierce n’a pas fait l’objet d’un audit manuel. Aucun test d’attaque n’a été exécuté contre la production.

## Vérification

Les résultats exécutés et les empreintes des journaux sont conservés dans [le registre de preuves](../tests/audit/review-polish-evidence-2026-09-22.json). Corrections applicatives : `7bd809a` ; sélection native des produits et nettoyage du harnais : `b377cf3` ; précondition de premier plan de l’émulateur CI : `be3d2a7`.

| Contrôle | Résultat |
|---|---|
| Flutter | 146 tests réussis, 4 tests nécessitant des fixtures omis par défaut ; contrats et deux tests de synchronisation exécutés séparément ; analyse sans diagnostic |
| Backend | 92 tests réussis : domaine, transactions, audit, sécurité, médias, notifications et email |
| Contrats/synchronisation | 45 endpoints HTTP, décodage Dart, deux parcours HTTP/SQLite/PostgreSQL ; génération reproductible |
| Outils de release | 37 tests réussis ; signatures non approuvées refusées ; package vérifié avant et après copie |
| Android natif | Parcours des trois rôles réussis en CI ; arrêt réel après vente locale, reprise unique (stock 7, version 3, points 30), refus caméra et vidéo hors ligne réussis |
| Dépendances/runtime | Aucun avis de vulnérabilité npm pour les dépendances de production au moment du contrôle ; image Docker construite et imports du runtime vérifiés |
| CI du code livré | [35792773050](https://github.com/haider0708/bio-balance-app/actions/runs/35792773050) : backend, Android, parcours Android et compilation iOS réussis ; iOS non signé |
| CI finale du harnais | [35793743555](https://github.com/haider0708/bio-balance-app/actions/runs/35793743555), commit `be3d2a7` : les quatre jobs réussissent avec l’émulateur éveillé et la précondition de premier plan |
| Mise à jour APK privée | Installation de 1.0.0+2 puis mise à jour vers 1.0.1+3 sur un émulateur neuf, sans effacement des données ; lancement et écran de connexion vérifiés par l’automatisation native |

Le quatrième test Flutter à fixture (téléchargement à travers Compose/Nginx) conserve sa preuve de déploiement antérieure ; il n’a pas été relancé dans cette passe. Les tests média backend et la lecture native hors ligne ont été relancés. Les captures du binaire de diffusion restent noires conformément à `FLAG_SECURE` ; les captures de présentation ci-dessus proviennent des widgets de test.

APK et AAB **1.0.1+3** construits depuis l’arbre propre `b377cf3`. Certificats APK/application et AAB/upload vérifiés séparément ; manifeste sans débogage, sauvegarde Android ni HTTP clair ; bibliothèques distribuées sans sections DWARF, alignement ZIP/ELF 16 Kio vérifié. Les symboles privés restent hors du package. Archive locale : `.artifacts/releases/biobalance-b377cf3c-android-signed.tar.gz`, SHA-256 `b68ed57b0389200e7ae0d502ab6e105bfe0cf3e51c9374428b5ba2da1e45708a`. Cette candidate n’est pas publiée ; la release publique v1.0.0 reste inchangée.

Les changements après `b377cf3` concernent le harnais CI et les preuves, sans modification du runtime mobile/backend ni de la configuration livrée. Une mesure fiable des tokens de cette seule passe n’est pas disponible : les agrégats du scan incluaient des historiques partiels et ne sont pas présentés comme une consommation de cette revue.

Échecs intermédiaires conservés : ffmpeg absent du premier environnement de test puis PATH corrigé ; fixture de contrat corrigée ; redondance d’import et erreur de nom dans un nouveau test corrigées ; montage initial des métriques corrigé après inspection visuelle. Un autofix Dart a altéré la section assets du pubspec pendant une compilation Android : le fichier a été restauré et ce premier parcours invalidé, puis reconstruit. Un choix de produit masqué par le clavier dans le harnais natif a été remplacé par une recherche explicite suivie de la fermeture du clavier. Un ancien contrôle caméra CI a échoué ; le parcours du commit livré est vert, et la CI garde désormais son émulateur éveillé avec une précondition explicite de premier plan. Le premier wrapper local du parcours des rôles s’est terminé par signal après toutes les assertions ; sa sortie propre est confirmée par le parcours CI. Les preuves finales portent sur la configuration corrigée.

## Acceptation restante

Les tests locaux ne remplacent pas les essais physiques Android 4 Go/iOS, la signature Apple, la distribution et les mises à jour Play/APK, la validation des données commerciales réelles et le pilote de cinq magasins pendant deux semaines. Ces portes restent ouvertes. Le [registre VPS](vps-readiness-2026-09-22.md) décrit les contrôles serveur déjà exécutés ; aucun autre site du VPS n’a été modifié dans cette revue. Les sauvegardes hors serveur et la haute disponibilité restent hors périmètre.
