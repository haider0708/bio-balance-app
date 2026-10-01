# Données initiales — 1er octobre 2026

**Le catalogue = 51 produits avec code-barres** : les 39 de votre fichier Excel + les 12 produits de biobalance.tn dont j’ai retrouvé le code-barres (10 repulpeurs LipojeN, Acnevit sérum et gel). Sans prix, complet.

| Champ | Renseigné |
|---|---|
| Nom, catégorie, contenance, description, conseils d’utilisation, photo, code-barres | 51 / 51 |
| Ingrédients (INCI) | 47 / 51 (manquent : LipojeN N°35 et N°37, Acnevit sérum et gel) |
| Gamme | 50 / 51 (l’Eyelash Growth Serum n’appartient à aucune gamme) |
| Précautions | 4 / 51 (uniquement quand une source les donne) |
| Prix | 0 — BioBalance les fixe dans l’application (A, B, C) |

## D’où vient chaque champ

1. **Votre liste Excel** : les 39 codes, la liste de référence.
2. **biobalance.tn** (vos pages) : noms, description, avantages, conseils d’utilisation en français, photo.
3. **Le fabricant, biobalance.com.tr** (pages officielles) : liste d’ingrédients INCI, contenance, mentions de formule (sans parfum, vegan…), mode d’emploi des déodorants.
4. **Barcode Lookup** (34 fiches sur 39) : produits absents du site (Eyelash, baumes Hello Clean, contour des yeux nuit), ingrédients et photos de secours.
5. **MaPara Tunisie** (revendeur) : seulement des listes d’ingrédients quand rien d’autre n’en donne.

## Codes-barres retrouvés (produits hors Excel)

| Produit | EAN-13 | Preuve |
|---|---|---|
| Repulpeur LipojeN N°03 Hot Chocolate | 8697711011122 | Barcode Lookup, lipojen.com |
| N°04 Rose Venus | 8697711011139 | Barcode Lookup, lipojen.com |
| N°05 Rosy Petal | 8697711011146 | Barcode Lookup (la même teinte N°5 y est nommée Pink Love), suite des numéros |
| N°07 High Society | 8697711011160 | Barcode Lookup, lipojen.com |
| N°10 Hot Red | 8697711011191 | Barcode Lookup, lipojen.com |
| N°31 Flamingo Love | 8697711011221 | Barcode Lookup |
| N°32 Coral Dream | 8697711011238 | Barcode Lookup |
| N°34 Fuchsia Vibes | 8697711011252 | Barcode Lookup |
| N°35 Candy Crush | 8697711011269 | cosmetista.me (SKU) |
| N°37 Cinnamon Roll | 8697711011283 | cosmetista.me (SKU) |
| Acnevit Anti-Acne Serum 30 ml | 8697711721014 | Amazon (numéro de modèle), puntofarma.com.py |
| Acnevit Anti-Acne Cleansing Gel 200 ml | 8697711721021 | Amazon (numéro de modèle), cosmetista.me (SKU) |

Les 12 codes sont des EAN-13 valides, tous distincts de ceux de votre liste.

## Production

51 produits actifs, tous ces champs écrits, prix de référence vides. Les données d’essai (grossiste de démonstration, commandes, vente d’essai, stock d’essai) ont été purgées en une transaction contrôlée, après sauvegarde ; vos groupes, magasins, comptes et vos propres données du 24-25 septembre sont intacts. Chaque modification est dans le journal d’audit.

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
