# Catalogue et démonstration — 22 septembre 2026

Le catalogue relie les 39 codes EAN-13 du classeur fourni à 51 références BioBalance. Les deux déodorants `8697711622410` et `8697711740411` restent des produits distincts, conformément à la décision du propriétaire. Les 12 références supplémentaires du site sans code dans le classeur restent recherchables manuellement : aucun code-barres n’est inventé.

Le [relevé CSV](data/catalogue-2026-09-22.csv) conserve nom, référence, code, prix TND à trois décimales et URLs de provenance. 42 prix viennent de `biobalance.tn` ; deux références absentes du site tunisien utilisent un prix observé chez MaPara Tunisie. Les prix sont des valeurs observées au moment de l’import, pas un engagement de disponibilité ou un tarif permanent.

## Sept prix explicitement fictifs

L’utilisateur a autorisé des prix de démonstration pour les références ci-dessous. Ces produits portent « prix démo » dans leur nom et une explication dans leur description. Les responsables reçoivent une configuration de magasin modifiable et leurs équipes une annonce volontaire expliquant la simulation.

| Code-barres | Produit | Prix démo TND |
|---|---|---:|
| 8697711622410 | Déodorant Dry & White distinct | 29,000 |
| 8697711722011 | Eye Lash 6 ml | 59,000 |
| 8697711601514 | Hello Clean Brightening | 49,000 |
| 8697711601538 | Hello Clean Deep Hydrating | 49,000 |
| 8697711601521 | Hello Clean Nourishing | 49,000 |
| 8697711601545 | Hello Clean Pore Downsizer | 49,000 |
| 8697711602139 | Advanced Night Recovery Eye 20 ml | 59,000 |

Les images viennent du site tunisien, du fabricant ou de fiches marchandes correspondant au produit. Le déodorant distinct et le sérum de nuit pour les yeux sont vérifiés par EAN affiché ; les quatre baumes sont rapprochés des pages fabricant par nom, actif et contenance. Les fichiers sont décodés, les sources et empreintes conservées, puis le pipeline média applicatif produit les images réellement attachées. Les sept images complémentaires sont converties en JPEG RGB, sans EXIF, limitées à 1 400 px avant traitement serveur.

## Magasins et scénarios

Cinq magasins portent le préfixe `DÉMO —` : Tunis/L’Aouina, Sfax/El Ain, Ariana, Sousse/Sahloul et Nabeul. Les noms/adresses s’inspirent des annuaires publics des commerces ; il ne s’agit pas de partenaires inscrits ou contactés. Deux organisations et sept comptes fictifs utilisent `@demo.biobalance.invalid`, sans invitation externe. Les accès sont conservés uniquement dans le dossier opérateur privé.

Chaque magasin possède les 51 configurations de produit et un stock d’ouverture fictif par lot. Des lots proches de péremption, périmés et des écarts de stock permettent de tester les filtres. Les 100 ventes, cinq corrections, cinq retours, dégâts et récompenses conservent les mouvements, révisions, points et acteurs des opérations ordinaires. Les commandes présentent réception complète, réception partielle avec complément expédié, colis non reçu, préparation et demande en attente. Un guide d’utilisation est publié ; cinq fiches produit restent en brouillon pour relecture métier.

## Reprise et passage aux données réelles

Les outils `scripts/catalog/` lient leur checkpoint à l’API, au compte et à l’empreinte du manifeste. Le premier import reste immuable ; les sept tarifs fictifs sont une modification distincte, versionnée et reprise avec les mêmes identifiants d’opération. Un produit modifié par une personne depuis l’import bloque son remplacement automatique. Les écritures de stock et points passent par les transactions métier, jamais par une réécriture directe des historiques.

Avant exploitation commerciale, valider les prix, les douze codes absents et les fiches de formation. Créer les magasins réels avec leurs stocks réellement comptés, puis désactiver les accès de démonstration. Ne pas transformer les ventes fictives en historique commercial en renommant simplement un magasin. Les anciens lots et mouvements restent auditables.

Le dossier `.artifacts/catalog-operations-2026-09-22/` contient les manifests privés, sources, checkpoints et résultats détaillés ; il est exclu de Git. Les mesures et états effectivement réussis sont consignés dans le registre d’implémentation et les preuves de déploiement.
