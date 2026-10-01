# Réception vérifiée, stock déclaré une fois — 1er octobre 2026

Candidate Android **1.4.0+18**, après 1.3.0+17. Migration additive `202610010001`.

## Règles

1. **Le QR fait foi.** Le responsable (ou le grossiste) scanne le colis : l’application affiche les lots et quantités du bon, en lecture seule. S’il confirme, le stock augmente exactement de ce que le bon liste. Le serveur ignore toute quantité envoyée avec un QR valide.
2. **Sans QR, rien ne bouge.** Le récepteur indique pourquoi il ne scanne pas et ce qu’il a reçu. La livraison passe à « en attente de validation par BioBalance » ; le stock ne change pas, la commande garde les unités « en route ». Cette déclaration est écrite une fois et ne change plus (trigger `Delivery_claim_once`).
3. **BioBalance valide** (`delivery.validate`, administrateur seul) : il voit l’expédié (lots du bon) à côté de la déclaration, corrige les quantités, justifie sa décision. Le magasin reçoit les quantités validées.
   - Unités en plus : prises sur le stock du grossiste.
   - Unités manquantes : « retournées » au dépôt (le grossiste avait menti) ou « perdues » ; si le magasin avait menti, BioBalance ajoute simplement les unités manquantes dans la validation. Une expédition de BioBalance n’a pas de dépôt : rien à ajuster.
   - BioBalance peut aussi réceptionner au nom d’un magasin (livraison encore « expédiée »).
4. **Perdu ou retourné : BioBalance seul.** Le grossiste ne peut plus que suivre (`tracing`) et ajouter une note.
5. **Le stock est déclaré une seule fois.** Au départ, le responsable ou le grossiste répond : « Avez-vous déjà du stock ? » — il le saisit une fois, ou déclare qu’il n’en a pas (choix définitif) et commande. Ensuite le stock n’arrive que par livraison ; il diminue par vente, signalement non conforme et décision de BioBalance. `stock.adjust` n’existe plus, `stock.receive` n’accepte que `opening` et refuse `OPENING_CLOSED` après la première déclaration (colonne `Store.openingClosedAt`). Les magasins et dépôts qui avaient déjà du stock sont fermés par la migration.
6. **L’heure d’une vente ne dépend pas du téléphone.** Chaque réponse du serveur recale une horloge de confiance (`TrustedClock`, en-tête `Date`) ; entre deux réponses elle avance sans pouvoir reculer, et la dernière ancre est conservée au redémarrage. Le serveur refuse les ventes datées du futur et ne retient jamais un taux de points antérieur à trois jours avant l’arrivée de la vente (`rateAt`).

`TICKET_SCAN_REQUIRED` n’existe plus : un reçu sans scan est toujours une déclaration à valider.

## Validation locale

- 107 tests d’intégration PostgreSQL (nouveaux : scan exact, déclaration en attente, correction dépôt/magasin, stock déclaré une fois, commande inconnue), 71 contrats HTTP décodés par le client Dart régénéré, tests Flutter (écran de validation, reçu par scan en lecture seule, projection hors ligne, horloge de confiance).

## Limites

- Les journées d’émulateur (`integration_test`, `tests/journeys`) n’ont pas été rejouées.
- Le scan par la caméra n’est vérifié que par tests d’interface ; il nécessite un second appareil affichant le QR.
