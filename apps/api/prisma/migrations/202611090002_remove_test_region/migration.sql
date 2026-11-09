-- The test region (the store reviewers' demonstration accounts) is gone: its rows were purged and its
-- code removed (last seen in the git tag `demo-region-last`). This takes its mechanism out of the
-- database too: the policies no longer hide a region from the admin, and a kept authenticator link (one
-- that never expired and could be opened again and again) is gone.

-- 1. Functions and policies that call the "hidden region" helpers are rewritten in place: an admin sees
--    every region (app_is_admin()), and a region is always visible.
DO $$
DECLARE
  f record;
  p record;
  def text;
  expr text;
  check_expr text;
  left_over int;
BEGIN
  FOR f IN
    SELECT fn.oid FROM pg_proc fn
    WHERE fn.pronamespace = 'public'::regnamespace
      AND fn.proname NOT IN ('app_admin_sees', 'app_region_visible', 'app_hidden_region')
      AND fn.prosrc ~ 'app_(admin_sees|region_visible|hidden_region)\('
  LOOP
    def := pg_get_functiondef(f.oid);
    def := regexp_replace(def, 'app_admin_sees\([^()]*\)', 'app_is_admin()', 'g');
    def := regexp_replace(def, 'app_region_visible\([^()]*\)', 'true', 'g');
    EXECUTE def;
  END LOOP;

  FOR p IN
    SELECT schemaname, tablename, policyname, qual, with_check FROM pg_policies
    WHERE qual ~ 'app_(admin_sees|region_visible)\(' OR with_check ~ 'app_(admin_sees|region_visible)\('
  LOOP
    expr := regexp_replace(coalesce(p.qual, ''), 'app_admin_sees\([^()]*\)', 'app_is_admin()', 'g');
    expr := regexp_replace(expr, 'app_region_visible\([^()]*\)', 'true', 'g');
    expr := regexp_replace(expr, ' AND true\)', ')', 'g');
    check_expr := regexp_replace(coalesce(p.with_check, ''), 'app_admin_sees\([^()]*\)', 'app_is_admin()', 'g');
    check_expr := regexp_replace(check_expr, 'app_region_visible\([^()]*\)', 'true', 'g');
    check_expr := regexp_replace(check_expr, ' AND true\)', ')', 'g');
    EXECUTE format('ALTER POLICY %I ON %I.%I%s%s', p.policyname, p.schemaname, p.tablename,
      CASE WHEN p.qual IS NULL THEN '' ELSE ' USING (' || expr || ')' END,
      CASE WHEN p.with_check IS NULL THEN '' ELSE ' WITH CHECK (' || check_expr || ')' END);
  END LOOP;

  -- Nothing may still call them before they are dropped.
  SELECT count(*) INTO left_over FROM pg_policies
    WHERE qual ~ 'app_(admin_sees|region_visible|hidden_region)\(' OR with_check ~ 'app_(admin_sees|region_visible|hidden_region)\(';
  IF left_over > 0 THEN
    RAISE EXCEPTION '% policies still use the hidden-region helpers', left_over;
  END IF;
END $$;

-- 2. Regions and people had no policy before the test region: back to that.
DROP POLICY "Region_visible" ON "Region";
ALTER TABLE "Region" NO FORCE ROW LEVEL SECURITY;
ALTER TABLE "Region" DISABLE ROW LEVEL SECURITY;
DROP POLICY "User_visible" ON "User";
ALTER TABLE "User" NO FORCE ROW LEVEL SECURITY;
ALTER TABLE "User" DISABLE ROW LEVEL SECURITY;

DROP FUNCTION app_admin_sees(uuid);
DROP FUNCTION app_region_visible(uuid);
DROP FUNCTION app_hidden_region();

-- 3. The flag itself.
DROP INDEX "Region_one_sandbox";
ALTER TABLE "Region" DROP COLUMN "sandbox";

-- 4. The routine jobs of the test region, finished or not.
DELETE FROM "Job" WHERE kind IN ('sandbox-approve', 'sandbox-sell', 'demo-restore');

-- 5. The "test position" verdict (no visit can carry it any more).
ALTER TYPE "PresenceVerdict" RENAME TO "PresenceVerdict_old";
CREATE TYPE "PresenceVerdict" AS ENUM ('VERIFIED', 'OUT_OF_RANGE', 'NO_FIX', 'NO_POSITION');
ALTER TABLE "VisitEvent" ALTER COLUMN "verdict" TYPE "PresenceVerdict" USING "verdict"::text::"PresenceVerdict";
DROP TYPE "PresenceVerdict_old";

-- 6. Authenticator links all expire: a link kept open for ever is closed, and the option is gone.
UPDATE "SetupLink" SET "secret" = NULL, "usedAt" = CURRENT_TIMESTAMP WHERE "keep" AND "secret" IS NOT NULL;
ALTER TABLE "SetupLink" DROP COLUMN "keep";
