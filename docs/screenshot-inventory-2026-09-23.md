# Inventaire visuel — 23 septembre 2026

Captures produites depuis les widgets Flutter réels avec fixtures synthétiques et une photo produit archivée de biobalance.tn. Aucun compte client ni code d’accès n’est photographié. Les couleurs, polices, formulaires et composants sont ceux de l’application.

- `group_navigation_test.dart` : réseau → Parahouse → Tunis → autre groupe, 360×800 et paysage 800×360, texte 100 % et 200 %, sauvegarde de brouillon refusant la navigation si disque plein.
- `visual_audit_test.dart` : 26 écrans en portrait et paysage 200 %, décodage photo réel, défilement et absence d’erreur de disposition ; 52 tests.
- `ui_test.dart` : rôles, erreurs hors connexion, sélecteurs recherchables et clavier, actions selon permissions.
- `role_journeys_test.dart` : interactions réelles Flutter/API/PostgreSQL ; activation, onboarding, vente/correction/retour, commandes, réception, cadeaux, annonces, formation et révocation.

## Captures

| Écran | Capture |
|---|---|
| Réseau administrateur | [Réseau](screenshots/redesign-network.png) |
| Groupe Parahouse | [Groupe](screenshots/redesign-group.png) |
| Magasin Tunis | [Magasin](screenshots/redesign-store.png) |
| Accueil vendeur | [Vendeur](screenshots/salesperson-home.png) |
| account | [Ouvrir](screenshots/audit-account.png) |
| activation | [Ouvrir](screenshots/audit-activation.png) |
| announcement | [Ouvrir](screenshots/audit-announcement.png) |
| article | [Ouvrir](screenshots/audit-article.png) |
| catalog | [Ouvrir](screenshots/audit-catalog.png) |
| help | [Ouvrir](screenshots/audit-help.png) |
| login | [Ouvrir](screenshots/audit-login.png) |
| notifications | [Ouvrir](screenshots/audit-notifications.png) |
| onboarding | [Ouvrir](screenshots/audit-onboarding.png) |
| order-editor | [Ouvrir](screenshots/audit-order-editor.png) |
| orders | [Ouvrir](screenshots/audit-orders.png) |
| product-settings | [Ouvrir](screenshots/audit-product-settings.png) |
| product | [Ouvrir](screenshots/audit-product.png) |
| receipt | [Ouvrir](screenshots/audit-receipt.png) |
| recovery | [Ouvrir](screenshots/audit-recovery.png) |
| reset | [Ouvrir](screenshots/audit-reset.png) |
| rewards | [Ouvrir](screenshots/audit-rewards.png) |
| sale-line | [Ouvrir](screenshots/audit-sale-line.png) |
| group-invitation | [Ouvrir](screenshots/audit-group-invitation.png) |
| sale | [Ouvrir](screenshots/audit-sale.png) |
| sales-history | [Ouvrir](screenshots/audit-sales-history.png) |
| stock-product | [Ouvrir](screenshots/audit-stock-product.png) |
| stock | [Ouvrir](screenshots/audit-stock.png) |
| store-settings | [Ouvrir](screenshots/audit-store-settings.png) |
| sync | [Ouvrir](screenshots/audit-sync.png) |
| team | [Ouvrir](screenshots/audit-team.png) |
| training-editor | [Ouvrir](screenshots/audit-training-editor.png) |
| training | [Ouvrir](screenshots/audit-training.png) |

## Revue et portée

Revue manuelle des planches de contacts : alignement des lignes, cadrage complet des emballages, contraste, libellés, unités TND/points, densité, priorité des actions et champs. Corrections réalisées : photo réelle dans les listes, glyphes cohérents, contraste, header défilant en paysage/texte agrandi, état du sélecteur et champs restaurés. Les captures des formulaires incluent des listes vides réalistes ; les erreurs et états d’accès sont également vérifiés par tests interactifs.

Ces captures ne qualifient pas la caméra physique, la lecture VoiceOver/TalkBack, la fluidité sur Samsung ou iOS, ni toutes les combinaisons possibles de contenu. La caméra et la vidéo sont exercées sur émulateur ; la qualification des appareils physiques reste enregistrée séparément. La mise à jour Samsung attend une connexion ADB autorisée.


## Retour Samsung — candidate 1.1.1+5

28 écrans sont revus en portrait et paysage à 200 %, complétés par les parcours clavier/retour Android et les sélecteurs. La page de récupération présente huit cases, les formulaires utilisent un seul défilement de page, le groupe est en haut à gauche et les commandes sont classées par étape. Les fixtures ventes et commandes incluent maintenant des lignes renseignées, pour contrôler vendeur/magasin et les intitulés. Les photos en fixture vérifient le cadrage ; les tests du vrai cache vérifient séparément leur résolution, téléchargement et reprise.

## Ajustement 1.1.2 — graphique et paramètres

- `interactive-sales-chart.png` : points tactiles, axes, date et valeurs exactes du jour, lien vers ses ventes. Vérifié également en paysage et à 200 % de texte.
- `settings-network.png` : accès commun aux paramètres et à l’administration. La capture 1.1.4 remplace celle-ci et retire la sélection redondante.
- `settings-store.png` : prix/points/seuils, équipe, guide, historiques et accès au groupe.

Les tests couvrent aussi l’absence de commandes de gestion pour le vendeur et la navigation du réseau vers les réglages du magasin.


## Graphique 1.1.3

- [Période mensuelle et bulle sélectionnée](screenshots/interactive-sales-chart.png) : trois mesures, halo, référence moyenne et accès au jour.
- [Période courte](screenshots/interactive-sales-chart-short.png) : jours sans ventes et sélection accessible.
- [Vue agrandie en paysage](screenshots/interactive-sales-chart-expanded.png) : périmètre, période, commandes compactes et tracé complet.

La capture mensuelle est désormais produite par `chart_exploration_test.dart`. Les assertions vérifient aussi la conservation du jour et du magasin dans les liens de ventes, l’affichage à 200 % et les animations réduites.

## Synchronisation 1.1.4

- [Opération à vérifier dans un autre magasin](screenshots/sync-account-recovery.png) : compte/téléphone, magasin explicite, état et résolution ; texte à 100 % et 200 % testé.
- [File vide](screenshots/audit-sync.png) : aucune opération restante dans l’ensemble du compte sur cet appareil.
- [Paramètres réseau](screenshots/settings-network.png) : informations et administration sans second sélecteur de groupe/magasin.
- [Paramètres magasin](screenshots/settings-store.png) : réglages et permissions conservés.

La file réelle du Samsung a été observée via sa hiérarchie d’accessibilité. La protection de capture du build signé reste active.
