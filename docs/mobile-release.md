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

Copier `config/mobile/production.example.json` vers `config/mobile/android.local.json` et renseigner uniquement l’origine HTTPS réelle et l’éventuel `AUTH_LINK_HOST`. Aucun paramètre Firebase n’est accepté. Les clés initiales ont été créées dans un répertoire privé hors dépôt ; voir [sécurité et signatures](security-hardening.md).

Pour le backend actuellement déployé, `config/mobile/production.json` contient déjà l’origine publique `https://api.galylio.com`, sans secret. La release GitHub `v1.0.0` utilise ce fichier et la version `1.0.0+2`.

```sh
python3 scripts/build-signed-android.py config/mobile/production.json /home/haydar/.local/share/biobalance/signing
```

La clé d’application signe l’APK ; la clé d’upload signe l’AAB. Vérification des empreintes publiques versionnées avant compilation, puis contrôle de la signature APK, de chaque entrée AAB, de l’alignement ELF/ZIP et de l’absence de DWARF dans l’APK. Flutter obfusque les builds de diffusion et conserve les symboles hors des fichiers de distribution. Le build Gradle refuse un release sans clé, sauf le mode de compilation explicitement choisi par le script.

L’inscription Google Play doit importer la même clé d’application pour permettre les mises à jour entre Google Play et APK privés. Une sauvegarde chiffrée des clés et la vérification des mises à jour sont obligatoires avant diffusion.

## iOS signé et TestFlight

Dans Xcode, enregistrer `tn.biobalance.app` dans l’équipe Apple existante, installer le certificat/profil de distribution correspondant. Copier `ios/Flutter/Signing.xcconfig.example` vers `Signing.xcconfig` et renseigner l’équipe ; copier l’exemple ExportOptions vers un fichier `.local.plist` avec la même équipe. Utiliser une configuration d’origine API HTTPS pour iOS ; aucun paramètre Firebase n’est requis.

Les entitlements de liens vérifiés sont conservés ; la capacité push n’est pas demandée dans cette version. Le script contrôle l’IPA exportée : équipe, identifiant, signature complète et absence de permission de débogage. Vérifier ensuite le profil et l’acceptation TestFlight sur macOS.

```sh
bash scripts/build-mobile-release.sh signed ios config/mobile/ios.local.json config/mobile/ExportOptions.local.plist
```

Vérifier l’archive et l’IPA avec Xcode Organizer/codesign, puis transmettre via le compte App Store Connect autorisé. Le script crée les fichiers ; il ne soumet rien automatiquement. Compléter métadonnées, confidentialité, déclarations de collecte, captures réelles et informations de revue à partir du comportement final ; aucune acceptation Apple/Google n’est présumée.

## Configuration et distribution

Utiliser des fichiers distincts staging/production et par plateforme. Ne pas changer le serveur d’une installation qui contient des opérations en attente : synchroniser/exporter le diagnostic puis utiliser une installation de test distincte si nécessaire. Les mots de passe et tokens restent dans le stockage sécurisé, jamais dans les paramètres de compilation.

Les workflows CI sont disponibles dans [GitHub Actions](https://github.com/haider0708/bio-balance-app/actions). Le job macOS compile sans signature ; la signature requiert un runner autorisé disposant des credentials ci-dessus. Avant pilote, suivre `release-gates.md` puis `pilot-plan.md`.

Depuis un arbre Git propre, créer le dossier de livraison :

```sh
python3 scripts/package-release.py .artifacts/releases/builds/LE_DOSSIER_CHOISI
```

Le package contient seulement des fichiers suivis et autorisés (documentation, contrat, migrations, configuration exemple, scripts et preuves résumées), une archive des sources du commit et les artefacts choisis. Le manifeste doit correspondre au commit propre et à l’empreinte des sources ; le packageur revalide les signatures APK/AAB contre les certificats versionnés, ou l’IPA contre l’équipe Apple sur macOS. Ces contrôles portent également sur les fichiers copiés. Un manifeste auto-déclaré ne prouve pas à lui seul la provenance du binaire : utiliser le script de build sur l’hôte de confiance. Aucun volume, secret, token de charge ou backup de données n’est copié. Un package compile-only reste explicitement non diffusable.

## Liens de compte HTTPS vérifiés

L’activation et la récupération utilisent un code manuel lorsque `ACTIVATION_URL` / `RECOVERY_URL` sont vides. Supprimer toute ancienne valeur `biobalance://` de l’environnement ; le serveur refuse cette configuration au démarrage.

Pour activer les liens, ajouter le champ public optionnel `AUTH_LINK_HOST` au JSON mobile et fournir les deux URL `https://HOTE/activate` et `https://HOTE/recover` au backend. Android utilise ce même champ dans son filtre App Links vérifié. Le script de release iOS écrit `ios/Flutter/AccountLinks.xcconfig` avec cet hôte ; activer Associated Domains dans l’équipe Apple. Un build Xcode manuel doit utiliser le même hôte dans cet xcconfig et dans les Dart defines.

Servir sur l’hôte détenu, sans redirection, les fichiers `/.well-known/assetlinks.json` (package `tn.biobalance.app`, SHA-256 du certificat de signature effectivement distribué) et `/.well-known/apple-app-site-association` (identifiant `TEAM_ID.tn.biobalance.app`, chemins `/activate` et `/recover`). Les modèles sont dans `config/account-links/`. Remplacer les valeurs exemples seulement avec les identités réelles ; ne pas publier les modèles. Ajouter une page de secours sans analytics, ressources tierces ou transfert de query, invitant à saisir le code du mail lorsque l’application n’est pas installée.

Vérifier l’association sur les appareils Android/iOS signés, y compris une installation concurrente déclarant un schéma privé, les liens expirés et une session déjà ouverte. La saisie manuelle reste disponible. Une configuration seule ne prouve pas que l’OS a vérifié le domaine.

## Installations privées pour tester les trois rôles

Le champ optionnel `ANDROID_INSTALLATION` accepte `vendeur2`, `admin`, `responsable` ou `vendeur`, uniquement pour Android. Sans ce champ, l’identité de production habituelle est inchangée. Voir [le guide de test manuel](manual-role-testing.md) pour les packages, comptes et configurations. Ces variantes n’ajoutent aucune permission et ne préremplissent aucun compte.
