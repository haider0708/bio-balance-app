# Données initiales — 1er octobre 2026

**Le catalogue = les 39 codes-barres de votre fichier Excel**, sans prix.

- Données : `data/initial-catalog/` (`produits.xlsx`, `.csv`, `.json`, 39 photos, `RAPPORT.md`).
- Production : 39 produits actifs, prix de référence vides (`priceStatus = missing`), noms, descriptions, catégories et gammes alignés sur ces données.
- Retirés : 13 produits hors liste. 12 sont supprimés, 1 (Rosy Petal N°05) est désactivé car mes essais y sont rattachés. Copie complète dans `data/deleted-products/` et `data/backups/` ; chaque suppression est aussi dans le journal d’audit (`catalog.delete`).
- Les anciens prix ne sont conservés que dans `data/deleted-products/anciens-prix-des-39-produits.csv`.

## Rechercher un produit par son code-barres

```sh
pip install playwright        # aucune installation de navigateur : l’outil pilote Brave
python3 scripts/catalog/barcode_fetch.py 8697711722011 8697711601514
python3 scripts/catalog/barcode_fetch.py --missing   # codes dont les données sont incomplètes
python3 scripts/catalog/build_initial_data.py --workbook "LISTE PRDT BIOBALANCE.xlsx"
```

L’outil ouvre une fenêtre Brave **vierge** (jamais vos sessions), visite une fiche à la fois à un rythme humain (8 à 20 s entre deux, 20 produits par passage), lit le titre, la marque, la description et la photo, et enregistre le résultat. Il ne contourne rien : si le site demande une vérification, la fenêtre reste ouverte, vous la faites, et il reprend. Les photos de revendeurs sont à remplacer par vos visuels officiels.
