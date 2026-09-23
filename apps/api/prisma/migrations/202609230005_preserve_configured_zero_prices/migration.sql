-- Legacy product configuration required an explicit selling price alongside
-- points. Preserve configured zero prices; an unconfigured default stays missing.
UPDATE "StoreProduct" SET "priceConfigured"=true
WHERE "pointsConfigured" AND NOT "priceConfigured";
