-- Phone numbers are stored in one form, "+216XXXXXXXX" (the app has done so since the numbers became
-- required). Older accounts kept what was typed: "28388764", "+216 52 204 094", "56 030 250". Bring them
-- to the same form; anything that is not a Tunisian mobile number is left as it is.
UPDATE "User" AS u
SET phone = '+216' || n.national
FROM (
  SELECT id,
    CASE
      WHEN d ~ '^00216[2-9][0-9]{7}$' THEN substr(d, 6)
      WHEN d ~ '^216[2-9][0-9]{7}$' THEN substr(d, 4)
      WHEN d ~ '^[2-9][0-9]{7}$' THEN d
    END AS national
  FROM (
    SELECT id, regexp_replace(regexp_replace(phone, '^\s*\+', '00'), '[^0-9]', '', 'g') AS d
    FROM "User"
    WHERE phone IS NOT NULL AND phone !~ '^\+216[0-9]{8}$'
  ) typed
) n
WHERE u.id = n.id AND n.national IS NOT NULL;
