# Nature du magasin — 29 septembre 2026

Candidate Android **1.1.11+15**, après 1.1.10+14. Un magasin est **soit une pharmacie, soit une
parapharmacie**. La nature se choisit à la création, se modifie par le responsable et
l’administrateur, et n’est jamais les deux à la fois.

## Règle confirmée

- Le responsable choisit la nature en ajoutant un magasin, avant le nom et l’adresse. Le choix est
  obligatoire et la saisie reste bloquée tant qu’il n’est pas fait.
- La nature se corrige ensuite dans « Paramètres du magasin », par le responsable du groupe comme
  par l’administrateur BioBalance, avec le même contrôle de version que le reste de la fiche.
- Aucune autre conséquence : le catalogue, les ventes, les commandes, les points et les récompenses
  sont identiques pour les deux natures. La séparation porte sur l’identité du magasin, pas sur son
  catalogue.
- La valeur est affichée dans la liste des magasins, la liste de tous les magasins, la fiche du
  magasin et le résumé du groupe.

## Aucun fait inventé

Les magasins créés avant cet attribut **gardent une nature inconnue**. La colonne est donc
nulable et rien n’est rétro-inventé : ni la migration, ni le script de démonstration, ni la
réinitialisation n’affectent une nature à un magasin existant. La fiche affiche « Nature non
renrenseillée » et demande la correction au prochain passage du responsable. Le reste de la
fiche — nom, adresse, ville, téléphone, image — n’est pas touché par cette absence.

## Application de la séparation

La nature est un scalaire unique, ce qui rend la double valeur structurellement impossible. Elle
est contrôlée à trois niveaux, du plus exposé au plus durable :

| Niveau | Contrôle |
|---|---|
| Requête HTTP | `nature` est un enum requis de « pharmacie » ou « parapharmacie », sans valeur par défaut |
| Service | `requireStoreNature` refuse toute valeur inconnue, y compris pour un appelant hors HTTP comme un test ou un script |
| PostgreSQL | Contrainte `Store_nature` : la valeur est absente, `pharmacie` ou `parapharmacie`, rien d’autre |

La migration `202609250001_store_nature` est additive : elle ajoute la colonne et la contrainte
sans toucher aux magasins existants, aux journaux de vente, de stock ou de points, ni à l’outbox.
L’audit `store.create` et `store.update` conserve automatiquement la nature dans son détail.

## Choix d’interface

Le champ **Nature du magasin** s’affiche comme deux choix exclusifs plutôt qu’une liste déroulante :
il n’y a que deux valeurs, elles se comparent d’un coup d’œil et un choix forcé est plus rapide
qu’une recherche. `FieldSpec.choice` ajoute ce rendu à l’éditeur partagé ; la sélection reste dans
le contrôleur du formulaire, donc un brouillon interrompu la restaure exactement comme un champ
texte. Un magasin sans nature connue démarre l’éditeur sur « Choisir… » au lieu de proposer une
valeur au hasard.

L’accès tactile de 48 dp et la lisibilité à 200 % de texte sont vérifiés sur un écran étroit :
les deux libellés restent entiers et le formulaire défile.

## Validation locale

- **133 tests backend** réussis, dont : création avec nature, refus d’une nature absente, refus
  d’une valeur inventée, refus de la contrainte PostgreSQL par un appelant qui contourne le
  service, correction par le responsable, et rejet d’une version périmée.
- **299 tests Flutter** réussis, dont la nature comme valeur unique, l’inconnu qui reste inconnu,
  l’aller-retour de payload, le choix obligatoire bloquant l’enregistrement, le remplacement d’une
  nature par l’autre, et le rendu étroit à 200 % de texte.
- **66 contrats HTTP** vérifiés sur l’API réelle, puis décodés par le client Dart généré.
- **Deux parcours HTTP/SQLite/PostgreSQL** réussis : 5 opérations, 6 mouvements, 3 révisions, stock
  7/1 version 7, 20 points ; la vente avec lot manquant ne crée aucune entrée fictive.
- Génération du contrat et du client Dart déterministes ; `flutter analyze` sans diagnostic ;
  APK debug compilé.

## Reste à faire avant diffusion

Comme pour les candidates précédentes, la compilation ne vaut ni installation physique ni pilote.
La mise à jour du Samsung reste en attente de connexion ADB, la dernière version installée
confirmée étant 1.1.8+12. Les APK/AAB signés 1.1.11+15 doivent être produits, et la qualification
tactile complète sur appareil reste à valider.
