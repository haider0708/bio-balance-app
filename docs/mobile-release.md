# Construire et transmettre les applications

Utiliser Flutter 3.47.5, les lockfiles, Java 17/SDK Android ; iOS exige macOS/Xcode. L’entrée de diffusion est exclusivement `lib/main.dart`. Les fichiers `integration_test/` et `main_test.dart` sont réservés aux harnais, leurs APK ne sont jamais distribués.

## Compilation locale sans credentials

```sh
bash scripts/build-mobile-release.sh compile-only android config/mobile/compile-only.json
# Sur macOS seulement :
bash scripts/build-mobile-release.sh compile-only ios config/mobile/compile-only.json
```

Les APK/AAB produits sous `.artifacts/releases/builds/` sont **non signés** et ciblent un domaine `.invalid` réservé. Ils prouvent une compilation, pas l’acceptation Play/App Store ni une connexion fonctionnelle. Le manifeste conserve commit, état modifié éventuel, empreinte des sources suivies et empreintes des fichiers. Le résultat unsigned APK n’est pas installable.

## Android signé

Copier `config/mobile/production.example.json` vers un fichier `android.local.json`, renseigner l’origine HTTPS réellement détenue et l’application Firebase Android. Ces valeurs Firebase sont publiques côté client ; ne jamais inclure la clé de service du worker. Fournir les variables `BIOBALANCE_KEYSTORE`, `BIOBALANCE_KEYSTORE_PASSWORD`, `BIOBALANCE_KEY_ALIAS`, `BIOBALANCE_KEY_PASSWORD` par le coffre de secrets du runner/local, sans les versionner ni les afficher.

```sh
bash scripts/build-mobile-release.sh signed android config/mobile/android.local.json
```

Le script exige la clé existante, construit APK et AAB, vérifie la signature APK, la présence/vérification de la signature du bundle et l’alignement ZIP/ELF des bibliothèques 64 bits pour les pages Android de 16 Kio. Comparer l’empreinte du certificat au certificat d’upload enregistré dans Play, tester installation puis mise à jour sans effacer SQLite/outbox. Mettre à jour `pubspec.yaml` avec un numéro de build supérieur avant une nouvelle diffusion. Configurer le projet Firebase pour `tn.biobalance.app` et les empreintes de signature requises.

## iOS signé et TestFlight

Dans Xcode, enregistrer `tn.biobalance.app` dans l’équipe Apple existante, activer Push Notifications, installer le certificat/profil correspondant et connecter APNs à Firebase. Copier `ios/Flutter/Signing.xcconfig.example` vers `Signing.xcconfig` et renseigner l’équipe ; copier l’exemple ExportOptions vers un fichier `.local.plist` avec la même équipe. Utiliser une configuration Firebase **iOS** distincte.

Les entitlements utilisent APNs `development` en debug et `production` en release/profile ; vérifier les entitlements de l’archive effectivement signée et le profil d’export. Le provisioning n’est pas déduit de cette configuration.

```sh
bash scripts/build-mobile-release.sh signed ios config/mobile/ios.local.json config/mobile/ExportOptions.local.plist
```

Vérifier l’archive et l’IPA avec Xcode Organizer/codesign, puis transmettre via le compte App Store Connect autorisé. Le script crée les fichiers ; il ne soumet rien automatiquement. Compléter métadonnées, confidentialité, déclarations de collecte, captures réelles et informations de revue à partir du comportement final ; aucune acceptation Apple/Google n’est présumée.

## Configuration et distribution

Utiliser des fichiers distincts staging/production et par plateforme. Ne pas changer le serveur d’une installation qui contient des opérations en attente : synchroniser/exporter le diagnostic puis utiliser une installation de test distincte si nécessaire. Les mots de passe et tokens restent dans le stockage sécurisé, jamais dans les paramètres de compilation.

Les workflows CI sont préparés mais nécessitent le dépôt distant. Le job macOS compile sans signature ; la signature requiert un runner autorisé disposant des credentials ci-dessus. Avant pilote, suivre `release-gates.md` puis `pilot-plan.md`.

Depuis un arbre Git propre, créer le dossier de livraison :

```sh
python3 scripts/package-release.py .artifacts/releases/builds/LE_DOSSIER_CHOISI
```

Le package contient seulement des fichiers suivis et autorisés (documentation, contrat, migrations, configuration exemple, scripts et preuves résumées), une archive des sources du commit et les artefacts choisis vérifiés par leur manifeste. Aucun volume, secret, token de charge ou backup de données n’est copié. Un package compile-only reste explicitement non diffusable.

## Liens de compte HTTPS vérifiés

L’activation et la récupération utilisent un code manuel lorsque `ACTIVATION_URL` / `RECOVERY_URL` sont vides. Supprimer toute ancienne valeur `biobalance://` de l’environnement ; le serveur refuse cette configuration au démarrage.

Pour activer les liens, ajouter le champ public optionnel `AUTH_LINK_HOST` au JSON mobile et fournir les deux URL `https://HOTE/activate` et `https://HOTE/recover` au backend. Android utilise ce même champ dans son filtre App Links vérifié. Le script de release iOS écrit `ios/Flutter/AccountLinks.xcconfig` avec cet hôte ; activer Associated Domains dans l’équipe Apple. Un build Xcode manuel doit utiliser le même hôte dans cet xcconfig et dans les Dart defines.

Servir sur l’hôte détenu, sans redirection, les fichiers `/.well-known/assetlinks.json` (package `tn.biobalance.app`, SHA-256 du certificat de signature effectivement distribué) et `/.well-known/apple-app-site-association` (identifiant `TEAM_ID.tn.biobalance.app`, chemins `/activate` et `/recover`). Les modèles sont dans `config/account-links/`. Remplacer les valeurs exemples seulement avec les identités réelles ; ne pas publier les modèles. Ajouter une page de secours sans analytics, ressources tierces ou transfert de query, invitant à saisir le code du mail lorsque l’application n’est pas installée.

Vérifier l’association sur les appareils Android/iOS signés, y compris une installation concurrente déclarant un schéma privé, les liens expirés et une session déjà ouverte. La saisie manuelle reste disponible. Une configuration seule ne prouve pas que l’OS a vérifié le domaine.
