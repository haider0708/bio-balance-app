# Chaîne des prix, réception et ventes — 2026-10-02

## Qui fixe quel prix
- **BioBalance → grossiste** (prix de gros) : fixé par BioBalance, par défaut ou par grossiste (écran Admin › Prix › Grossistes).
- **Fournisseur → magasin** (prix d’approvisionnement) : fixé par **le fournisseur qui livre**. BioBalance fixe sa propre liste ; **chaque grossiste fixe la sienne** (Paramètres du dépôt › Prix aux magasins). Une liste = un prix par produit pour tous les magasins ; BioBalance garde en plus des exceptions par magasin.
- **Magasin → client** (prix de vente) : fixé par le responsable du magasin. Il est averti, et doit confirmer, s’il vend sous son prix d’achat.

`PriceVersion.supplierOrganizationId` (migration `202610020001`) distingue les listes : NULL est la liste de BioBalance, donc tous les prix existants sont inchangés.

## Commandes
Une commande est chiffrée à sa création avec la liste de BioBalance. Quand BioBalance l’attribue à un grossiste, ses lignes sont rechiffrées avec **la liste de ce grossiste** (refus `SUPPLIER_PRICE_MISSING` s’il n’a pas fixé un prix) ; reprise par BioBalance : liste de BioBalance. Rien n’est rechiffré une fois qu’une livraison a commencé ni si le fournisseur ne change pas.

## Ventes
Un vendeur ne fixe pas le prix : le serveur n’accepte que le prix en vigueur du magasin (à la date de la vente ou aujourd’hui, ou le prix déjà présent sur la ligne corrigée) — `PRICE_FIXED`, `PRICE_NOT_SET`. Il peut ajouter une remarque (200 caractères) par ligne. Le responsable et BioBalance peuvent encore appliquer un autre prix (remise).

## Réception
Quantité reçue par lot, dont abîmées et refusées. Avec le QR, quantités, lots et dates sont celles du bon, mais le magasin peut **signaler l’état** (unités abîmées → stock non vendable ; refusées → non stockées) avec une explication obligatoire (`flags` de `delivery.receive`) ; BioBalance est notifié.

## Écrans
Stock et notifications par segments avec compteurs ; alertes du tableau de bord par segment (Stock, Péremption, Livraisons, Écarts) ; sélecteur de date partout où une péremption est saisie.
