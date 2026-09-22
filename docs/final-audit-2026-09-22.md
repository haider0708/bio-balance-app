# Audit final et qualification — 22 septembre 2026

Point de départ : `584f40f54a472950962c36e5c6cb81db0fa66afa`, branche `codex/biobalance-app`. Cette passe examine les frontières d’identité, les transactions et historiques, la synchronisation locale, les médias/workers, les interfaces et la distribution. Les corrections conservent les règles approuvées : ventes réelles même en cas de manque de stock, lots déclarés sans réception fictive, TND exact, points à la première synchronisation et isolation compte/magasin.

**Les défauts confirmés ci-dessous sont corrigés. La diffusion en production reste soumise aux vérifications externes du registre [Conditions de diffusion](release-gates.md).** Les tests locaux ne prouvent ni l’absence universelle de vulnérabilités ni la fluidité sur un appareil physique non testé.

## Constats et corrections

| Constat reproduit ou confirmé | Correction et preuve |
|---|---|
| Une invitation pouvait encore accorder des droits après révocation des droits de son émetteur | L’activation relit l’émetteur et son autorité actuelle dans la transaction : administrateur actif, propriétaire actif de l’organisation ou responsable actif du magasin. Émetteur désactivé, non attribuable ou privé de gestion refusé ; propriétaire autorisé conservé. Tests PostgreSQL restreint. |
| Un code de récupération pouvait modifier le mot de passe d’un compte désactivé | État actuel revérifié avant consommation du code et modification du hash. Le refus ne modifie ni compte ni code. Test PostgreSQL ; récupération normale déjà couverte par l’audit précédent. |
| Les paramètres Keychain iOS permettaient la migration du token par sauvegarde chiffrée | Service distinct `tn.biobalance.session.v2`, accessibilité `unlocked_this_device`, synchronisation iCloud désactivée. Suppression de l’ancienne entrée sans la réutiliser ; connexion requise après mise à jour d’une installation ancienne. SQLite et outbox conservés. Options/reprise vérifiées localement ; transfert natif sur deux iPhone encore à vérifier. |
| Un échec de relecture après enregistrement SQLite transformait une vente/réception réussie en erreur et invitait à la ressaisir | Séparation entre transaction durable et actualisation de l’affichage. Vente terminée et appels concurrents ne créent qu’une opération ; message explicite si l’affichage ne peut être actualisé. Même traitement appliqué aux retours et mouvements saisis. Tests avant/après avec panne injectée après commit réel. |
| Deux retraits rapides de lignes pouvaient réintroduire la première ligne retirée | État immuable actualisé immédiatement, écritures de brouillon sérialisées. La vente attend leur fin avant de compléter le brouillon ; la sortie du compte attend la soumission engagée. Tests concurrence et absence de brouillon recréé. |
| Une lecture de brouillon ou de cache échouée pouvait laisser l’espace en chargement ou exposer un éditeur vide | Restauration explicite avec saisie désactivée, erreur et nouvelle tentative ; initialisation et changement de magasin récupérables. Les relectures tardives vérifient la sélection après les opérations asynchrones. Tests panne de stockage et reprise. |
| Une erreur d’effacement du brouillon pouvait faire apparaître un formulaire accepté comme échoué | Soumission marquée terminée avant nettoyage, avertissement distinct si nettoyage impossible, nouvelle soumission désactivée même si le formulaire est la route racine. |
| Les formulaires de dommage/ajustement partageaient un brouillon sans identité de lot ; les retours étaient nettoyés séparément de l’outbox | Identifiants explicites par lot/vente, cible affichée, magasin capturé. Brouillon terminé dans la transaction de la commande ; écritures de brouillon gelées pendant la soumission, y compris réceptions. Tests de séparation des lots et de garde de sortie après commit. Les anciens brouillons non attribuables restent conservés dans SQLite et ne sont pas appliqués automatiquement à un autre lot. |
| Des pages de snapshot expirées pouvaient rester indéfiniment si leur utilisateur ne revenait pas | Maintenance globale par lots de 1 000, fonction SQL limitée à la suppression des pages expirées et au retour d’un nombre. Aucun droit de lecture inter-magasin accordé au rôle applicatif. Test conservant les pages valides et vérifiant l’absence de lecture globale. |
| Les emails d’invitation/récupération définitivement échoués conservaient leurs codes dans les jobs | Payload effacé à l’échec terminal, état et code de diagnostic conservés. Maintenance des anciens échecs ; emails encore en attente conservés pour la reprise. |

La migration additive `202609220004_snapshot_cleanup` ne réécrit aucune vente, révision, opération, écriture de stock ou de points. Appliquer les migrations avec l’identité de migration puis accorder au rôle applicatif la capacité étroite prévue par `scripts/provision-role.sql`. Les politiques RLS ordinaires restent actives ; la fonction n’accepte ni identifiant de magasin ni SQL fourni par le client.

## Revue sécurité et couverture

Scan Standard finalisé/indexé : `6e51883b-fab7-40fd-b8a2-a4827a65a56a`. Le [rapport généré du code de départ](../.artifacts/evidence/final-audit-2026-09-22/security/report.md), son manifeste et les JSON canoniques sont conservés localement. Ce rapport décrit trois constats avant correction (un élevé, deux moyens), pas trois vulnérabilités volontairement laissées ouvertes. Les preuves de correction sont les tests et fichiers de cette passe.

La couverture est explicitement partielle : revue des frontières et fichiers applicatifs pertinents, audit indépendant et investigations ciblées ; les 392 fichiers de l’inventaire ne sont pas tous assimilés à des fichiers relus exhaustivement. Les binaires, ressources et dépendances tierces ne sont pas certifiés par cette revue. Les attaques supposant déjà un compte administrateur ou un hôte de compilation compromis ne sont pas présentées comme une élévation de privilèges démontrée. Le dépassement d’une quantité commandée lors d’une réception réelle et la vente d’un produit global sans configuration de points ne sont pas interdits par les règles produit et n’ont pas été artificiellement bloqués.

Le compteur retourné par l’outil indique **21 515 665 tokens**, dont 21 354 913 en entrée et 160 752 en sortie, avec couverture de mesure **partielle** et avertissement `rollout_record_invalid`. Il s’agit de la télémétrie agrégée fournie par l’outil, pas d’une estimation vérifiée de facturation ou de consommation propre à cette seule passe.

## Vérifications du code corrigé

Les commandes sont exécutées localement ; les journaux bruts restent sous `.artifacts/` et doivent être expurgés avant partage. Le résumé versionné est [tests/audit/final-evidence-2026-09-22.json](../tests/audit/final-evidence-2026-09-22.json).

| Vérification | Résultat |
|---|---|
| Build TypeScript / formatage / analyse Dart | Réussis, aucun constat d’analyse |
| Backend domaine/reprise, intégration, audit, sécurité, médias, notifications | 68 tests réussis : 10 + 22 + 14 + 13 + 4 + 5 |
| Flutter unité/widgets | 130 réussis ; quatre scénarios nécessitant leur harnais serveur exclus de cette commande |
| Contrats HTTP et décodage Dart | 45 endpoints validés, aller-retour JSON réussi, génération sans dérive |
| HTTP + SQLite + PostgreSQL | Deux parcours réussis ; cinq opérations, six mouvements, trois révisions, stock 7/1 version 7 et 20 points ; lot manquant sans entrée fictive |
| Scripts Python de signature/configuration/backup | 14 tests réussis |
| Audit des dépendances npm de production | Aucun avis connu retourné le 22 septembre ; ne remplace pas une revue de dépendances |
| UI des rôles | Matrice téléphone/paysage/tablette et texte 100 %/200 %, états hors connexion avec erreur et file en attente, configuration téléphone et formulaires clavier vérifiés |
| Parcours Android des trois rôles | Réussis sur émulateur API 36 avec HTTP/PostgreSQL isolé ; stock 21, points 20, réservation 0, trois révisions, réception et remise de cadeau confirmées |
| Reprise Android et vidéo | Assertions réussies : arrêt réel, même compte/ID/payload, une vente, stock 7 v3, 30 points ; caméra refusée et vidéo H.264 vérifiée jouée hors ligne. Préparation manuelle de l’émulateur nécessaire, voir note. |
| Entrée normale Android `lib/main.dart` | Build/lancement et hot reload réussis ; aucune erreur runtime rapportée |
| Compose et builds release | Résultats finaux consignés ci-dessous après exécution |

La suite Flutter complète du code final compte 130 tests réussis ; les quatre scénarios dépendant d’un serveur sont exécutés avec leur harnais dédié.

Deux essais de reprise Android ont échoué sur l’étape caméra alors que la vente était déjà restaurée/synchronisée : dialogue System UI ANR et demande de permission orpheline dans l’émulateur. Le harnais pose et vérifie désormais les drapeaux de refus après installation de l’APK. Pour la passe concluante, l’émulateur a été redémarré sans snapshot, le dialogue système fermé, le contrôleur de permission orphelin arrêté et l’activité relancée via ADB avant les assertions. Cette intervention de préparation est conservée dans les preuves ; ce résultat ne constitue pas une exécution native entièrement autonome ni une mesure sur téléphone réel. Le refus de caméra a ensuite été vérifié par le harnais, puis le lecteur natif et les effets SQL ont passé leurs assertions. Le parcours complet des trois rôles a ensuite été exécuté de façon autonome sur le code final et a réussi en 2 min 55 s.

Les premières régressions ont reproduit les défauts d’autorité d’invitation, de récupération désactivée, de soumission après commit et d’éditions concurrentes. La première commande de test média n’avait pas FFmpeg dans son PATH ; la passe avec le binaire local et ses bibliothèques a réussi. Aucun test ignoré ou échec de harnais n’est compté comme réussite.

## Limites de qualification

- Dépôt distant/CI Linux et macOS, Xcode, équipe/profils Apple et TestFlight non fournis.
- Domaine/VPS/DNS/SMTP réels, sécurité SSH/firewall, ACME et alertes externes à vérifier sur la cible.
- Signature Android locale préparée auparavant ; inscription Play avec la même clé applicative, sauvegarde privée de clé, builds ciblant le vrai VPS et mises à jour entre Play/APK à valider avant diffusion.
- Android physique de 4 Go et iOS : mesures de démarrage, recherche, enregistrement, cadence, mémoire/batterie/caméra, accessibilité et transfert de sauvegarde. Les résultats d’émulateur ne remplacent pas ces mesures.
- Pilote de cinq magasins pendant au moins deux semaines, sur les deux plateformes et les trois rôles, puis résolution de ses incidents.
- Firebase reste retiré. Notifications dans la boîte VPS ; alertes OS app fermée reportées. Attestation Play Integrity/App Attest et pinning non actifs.
- Haute disponibilité et sauvegarde hors serveur restent reportées ; restauration locale ne couvre pas la destruction du VPS.
