# Données initiales — 1er octobre 2026

**Le catalogue = les 39 codes-barres de votre fichier Excel**, sans prix, complet.

| Champ | Renseigné |
|---|---|
| Nom, catégorie, contenance, description, conseils d’utilisation, ingrédients (INCI), photo | 39 / 39 |
| Gamme | 38 / 39 (l’Eyelash Growth Serum n’appartient à aucune gamme) |
| Précautions | 4 / 39 (uniquement quand une source les donne) |
| Prix | 0 — BioBalance les fixe dans l’application (A, B, C) |

## D’où vient chaque champ

1. **Votre liste Excel** : les 39 codes, la liste de référence.
2. **biobalance.tn** (vos pages) : noms, description, avantages, conseils d’utilisation en français, photo.
3. **Le fabricant, biobalance.com.tr** (pages officielles) : liste d’ingrédients INCI, contenance, mentions de formule (sans parfum, vegan…), mode d’emploi des déodorants.
4. **Barcode Lookup** (34 fiches sur 39) : produits absents du site (Eyelash, baumes Hello Clean, contour des yeux nuit), ingrédients et photos de secours.
5. **MaPara Tunisie** (revendeur) : seulement des listes d’ingrédients quand rien d’autre n’en donne.

## Production

39 produits actifs, tous ces champs écrits, prix de référence vides. 12 produits hors liste supprimés (copie dans `data/deleted-products/`), 1 désactivé (Rosy Petal N°05, rattaché à mes essais). Chaque modification est dans le journal d’audit.

## Reconstruire ou compléter

```sh
pip install playwright openpyxl requests beautifulsoup4 lxml          # aucun navigateur à télécharger
python3 scripts/catalog/barcode_fetch.py 8697711722011 8697711601514   # fiches Barcode Lookup, par code-barres
python3 scripts/catalog/barcode_fetch.py --missing                    # codes dont des données manquent
python3 scripts/catalog/crawl_biobalance_site.py [--manufacturer|--mapara]
python3 scripts/catalog/build_initial_data.py --workbook "LISTE PRDT BIOBALANCE.xlsx"
```

`barcode_fetch.py` ouvre une fenêtre Brave **vierge** (jamais vos sessions), visite une fiche à la fois à un rythme humain (5 à 20 s), lit titre, marque, description, ingrédients et photo, puis enregistre. Il ne contourne rien : si le site demande une vérification, vous la faites dans la fenêtre et il reprend.

Les photos de revendeurs (Barcode Lookup, MaPara) sont à remplacer par vos visuels officiels si vous en avez.
