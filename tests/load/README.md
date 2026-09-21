# Charge avant pilote élargi

Ce scénario k6 mesure 100 requêtes/s pendant cinq minutes puis 200/s pendant trente secondes, avec 90 % de lectures et 10 % de ventes. Il ne constitue pas une preuve de capacité tant qu’il n’a pas été exécuté sur le VPS de référence.

Utiliser **une base staging isolée**, migrée, avec 500 magasins, 5 000 comptes synthétiques et plusieurs millions de ventes. Les écritures sont réelles dans cette base. Ne jamais utiliser de comptes partenaires ou l’URL de production.

Préparer un JSON privé (mode 0600), un élément par magasin : `token` de session valide, `organizationId`, `storeId`, `productId`, `lotId` non périmé, `catalogRevision` obtenu par snapshot. Chaque vendeur doit avoir accès uniquement à son magasin ; les lots doivent contenir assez d’unités. Mettre ce fichier dans `.volumes`, exclu de Git.

```sh
k6 run -e BASE_URL=https://staging.example.com -e FIXTURES=/private/load-fixtures.json --summary-export=.volumes/load-summary.json tests/load/api.js
```

Mesurer depuis le réseau du VPS pour isoler la latence serveur ; répéter depuis un téléphone pour la latence utilisateur. Archiver le résumé k6, les caractéristiques machine, l’image applicative, les volumes de données, les journaux de requêtes expurgés, CPU/RAM/disque et la latence PostgreSQL. Vérifier les refus métier en plus des statuts HTTP. Exécuter ensuite les requêtes de cohérence stock/points sur cette base. Les seuils de ce fichier sont ceux du plan, pas des résultats déjà obtenus.
