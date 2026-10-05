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

## Mise à jour 2026-10-05

### Prix : défaut puis exceptions
Chaque niveau a une liste **par défaut** (tous les grossistes ; tous les magasins livrés par BioBalance) et des **prix particuliers** par grossiste ou par magasin. Un prix particulier se **retire** (`clear`, migration `202610050002`) : le grossiste ou le magasin suit de nouveau le défaut ; l’historique garde les deux. Écran Admin › Prix : la liste par défaut d’abord, puis chaque partie avec le badge « Prix par défaut » / « Prix particulier ».

### Points et récompenses : défaut puis exceptions
`PointsDefault` (barème par défaut, magasins ou grossistes) et `RewardTemplate` (récompenses par défaut), migration `202610050003`. Les défauts sont **copiés** dans chaque magasin ou dépôt (et dans tout nouveau magasin ou dépôt) : ventes, demandes, historique et sécurité par ligne restent inchangés. Un barème particulier (`StoreProduct.pointsException`) n’est pas touché par un changement du défaut et peut revenir au défaut. Une récompense par défaut est visible de tous et ne se modifie qu’à un endroit. Écran Admin › Points et récompenses.

### Réception avec QR
Le magasin voit le contenu du bon ; s’il correspond, il scanne et indique lot par lot les unités abîmées et refusées (raison obligatoire). Sinon il **refuse le colis** (`delivery.refuse`) : rien n’entre en stock, BioBalance **approuve** le retour (`delivery.resolve` « returned » : le stock du grossiste revient dans ses lots, la commande peut être réexpédiée) ou **rejette** le refus (« reopen » : le magasin doit réceptionner).

### Réception sans QR
BioBalance retient **une quantité par lot, valable pour les deux** : le magasin la reçoit, l’écart revient dans le lot du grossiste ou en sort. Les lots retenus sont ceux du bon (`LOT_NOT_SHIPPED` sinon). BioBalance indique qui est à l’origine de l’écart (`responsibility` : grossiste, magasin, transport, aucun), enregistré et notifié aux deux.

### Qualité
BioBalance peut retenir une partie d’un signalement (le reste redevient vendable, jamais pour un produit périmé) et indiquer le responsable ; l’expéditeur est notifié s’il est mis en cause (migration `202610050001`).

### Grossiste
Un grossiste travaille seul : ni équipe, ni guide, ni droit de créer un groupe (le script de remise à zéro ne lui en redonne plus).
