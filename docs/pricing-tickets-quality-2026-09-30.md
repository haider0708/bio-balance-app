# Prix, bons de livraison et produits non conformes — 30 septembre 2026

Candidate Android **1.3.0+17**, après 1.2.0+16. Non déployée : les trois migrations (`202609300002` à `202609300004`), le backend et les APK restent à produire et à installer.

## 1. Cycle des prix

Trois niveaux, un historique **append-only** (`PriceVersion`) :

| Niveau | Qui paie | Qui le fixe | Qui le voit |
|---|---|---|---|
| **Gros** (A) | le grossiste | BioBalance | BioBalance, le grossiste concerné |
| **Approvisionnement** (B) | le magasin, que BioBalance ou un grossiste livre | BioBalance | BioBalance, le responsable du magasin, le grossiste (prix par défaut) |
| **Vente** (C) | le client | le responsable du magasin | BioBalance, le responsable et le vendeur de ce magasin |

- Un prix particulier (un grossiste, un magasin) l’emporte sur le prix par défaut, quel que soit son âge.
- Chaque changement ajoute une ligne : qui, quand, pourquoi, niveau, portée. Rien n’est modifié ni supprimé (triggers PostgreSQL). Les prix existants deviennent la première version ; aucune vente passée n’est modifiée.
- Un niveau non autorisé est toujours `null` dans les réponses, jamais un autre prix. Le prix de référence du catalogue n’est visible que de BioBalance.
- L’historique des points par unité (`PointsRateVersion`) suit la même règle.
- Chaque **ligne de commande** fixe son prix d’approvisionnement (gros pour un dépôt) à la création ; un changement ultérieur ne modifie ni commande, ni bon, ni perte déjà enregistrés. Une modification de commande garde les prix existants et fixe celui d’un produit ajouté.
- Chaque **ligne de vente** garde le prix facturé et le prix de vente du magasin à la date de la vente (`listPriceMillimes`, inconnu plutôt qu’inventé avant le premier prix). Une correction garde le prix de la première acceptation.
- **Points** : le taux en vigueur à la date de la vente s’applique pour une vente reçue dans les 14 jours ; au-delà, le taux à l’acceptation. Sans historique de taux pour un produit, le taux courant s’applique. Un taux modifié ne réécrit jamais une vente ni une écriture de points passées.

## 2. Bon de livraison avec QR

1. La commande arrive à BioBalance, qui la traite ou l’attribue à un grossiste. L’expéditeur prépare, puis **déclare les lots** : numéro de lot, péremption, quantité. Un grossiste choisit des lots de son dépôt ; BioBalance, qui ne suit pas son propre stock, saisit le lot et la péremption. Un lot périmé ne peut pas être expédié.
2. Le serveur émet le **bon** `BL-AAAA-NNNNNN` avec les lots, les quantités et les prix fixés sur la commande. Il n’est jamais modifié.
3. Le **QR** (`BB1.<livraison>.<code>`) est montré à l’expéditeur seul, qui le partage en image pour l’imprimer. Le code est dérivé côté serveur de la livraison et de la version du bon ; il prouve le colis, sans révéler son contenu. Le responsable du magasin ne le voit pas dans son application.
4. À la réception, le responsable **scanne le colis**. L’application propose les lots annoncés ; il confirme ou corrige quantité, lot et état. Le stock augmente à cet instant, sous les lots du bon, et une différence ouvre un incident comme avant.
5. **Renouveler** le QR (perdu, abîmé) est réservé à l’expéditeur : l’ancien code cesse de fonctionner, le numéro reste. Un bon reçu ne se renouvelle pas.
6. Sans scan, le responsable indique pourquoi ; la réception est enregistrée comme faite sans scan et **signalée à BioBalance**. `TICKET_SCAN_REQUIRED=true` refuse toute réception sans scan ni motif ; par défaut elle est acceptée pour que les anciennes versions continuent de fonctionner. Un lot reçu que le bon ne liste pas est enregistré dans la réception.

## 3. Produits abîmés ou périmés

Le responsable (ou le grossiste pour son dépôt) **signale** un lot et une quantité : les unités quittent le stock vendable tout de suite. Une ligne `QualityFlag` garde le lot tel qu’il était, le signalant, la remarque et le bon de livraison d’origine. **BioBalance seul décide** : retirer du stock pour de bon (la perte est valorisée au prix de la livraison d’origine) ou remettre en vente si le signalement était injustifié. Un produit périmé n’est jamais remis en vente. Une décision est définitive (trigger PostgreSQL). Le retour d’une livraison en transit est aussi décidé par BioBalance seul ; une livraison perdue ne remet rien dans le dépôt.

## Validation locale

- **Backend :** 102 tests d’intégration PostgreSQL dont l’historique des prix (visibilité par rôle, priorité des prix particuliers, immutabilité), les bons (numérotation, QR valide/invalide/renouvelé, réception sans scan, lot hors bon), les signalements (stock, décision, valeur, finalité) et les ventes (prix de la date, taux de la date, corrections, ventes tardives). Audit 14, sécurité 10, notifications 5, email 19, domaine 19, médias 5.
- **71 contrats HTTP** vérifiés sur l’API réelle puis décodés par le client Dart régénéré ; dérive nulle.
- **Flutter :** tests de lecture du QR, réception par scan, déclaration des lots, visibilité des prix par rôle et projection hors ligne des signalements.

## Limites connues

- Une vente synchronisée tardivement peut choisir le taux de points de sa date déclarée (14 jours) : la date vient du téléphone. Limite acceptée ; chaque vente reste tracée et visible de BioBalance.
- Aucune installation sur téléphone ; l’écran du bon, le scan et les écrans de décision sont essayés seulement par des tests d’interface. Aucune qualification iOS.
- Les scripts `reset-business-keep-*.sql` ont reçu les nouvelles tables mais n’ont pas été rejoués.
- Les prix d’approvisionnement et de gros se définissent produit par produit ; l’import CSV de prix n’existe pas encore.
- Pas de facturation ni de paiement : seules des valeurs sont tracées.
- Le rapport de pertes se limite à la liste des décisions ; il n’y a pas encore de total par période.
