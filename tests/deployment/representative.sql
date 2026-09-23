SELECT json_build_object(
  'stores',(SELECT count(*) FROM "Store"),
  'sales',(SELECT count(*) FROM "Sale"),
  'revisions',(SELECT count(*) FROM "SaleRevision"),
  'movements',(SELECT count(*) FROM "StockMovement"),
  'sellable',(SELECT COALESCE(sum(sellable),0) FROM "InventoryLot"),
  'versions',(SELECT COALESCE(sum(version),0) FROM "InventoryLot"),
  'points',(SELECT COALESCE(sum(balance),0)::text FROM "PointsAccount"),
  'reportSales',(SELECT count(*) FROM "SalesContribution"),
  'reportNet',(SELECT COALESCE(sum("netMillimes"),0)::text FROM "SalesDay"),
  'thumbnails',(SELECT string_agg("thumbnailSha256",',' ORDER BY id) FROM "MediaAsset" WHERE status='ready'),
  'media',(SELECT string_agg(sha256,',' ORDER BY id) FROM "MediaAsset" WHERE status='ready')
);
