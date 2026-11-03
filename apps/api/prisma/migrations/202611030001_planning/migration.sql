-- Planning for the responsables: visits to the stores and grossistes of their region, a position for
-- each place, and the evidence of being there (one check-in and one check-out per visit, the
-- position given at that moment, never a trail). Kept 12 months.

CREATE TYPE "VisitKind" AS ENUM ('COUNT', 'DELIVERY', 'TRAINING', 'FOLLOW_UP', 'OTHER');
CREATE TYPE "VisitStatus" AS ENUM ('PLANNED', 'ON_SITE', 'DONE', 'MISSED', 'CANCELLED');
CREATE TYPE "VisitEventKind" AS ENUM ('CHECK_IN', 'CHECK_OUT');
CREATE TYPE "PresenceVerdict" AS ENUM ('VERIFIED', 'OUT_OF_RANGE', 'NO_FIX', 'NO_POSITION', 'SANDBOX');

-- Where each place is.
ALTER TABLE "Pdv"
  ADD COLUMN "latitude" DOUBLE PRECISION,
  ADD COLUMN "longitude" DOUBLE PRECISION,
  ADD COLUMN "positionAccuracyM" DOUBLE PRECISION,
  ADD COLUMN "positionSetById" UUID,
  ADD COLUMN "positionSetAt" TIMESTAMP(3),
  ADD COLUMN "positionLocked" BOOLEAN NOT NULL DEFAULT false,
  ADD CONSTRAINT "Pdv_position_check" CHECK (
    ("latitude" IS NULL AND "longitude" IS NULL)
    OR ("latitude" BETWEEN -90 AND 90 AND "longitude" BETWEEN -180 AND 180));
ALTER TABLE "Depot"
  ADD COLUMN "latitude" DOUBLE PRECISION,
  ADD COLUMN "longitude" DOUBLE PRECISION,
  ADD COLUMN "positionAccuracyM" DOUBLE PRECISION,
  ADD COLUMN "positionSetById" UUID,
  ADD COLUMN "positionSetAt" TIMESTAMP(3),
  ADD COLUMN "positionLocked" BOOLEAN NOT NULL DEFAULT false,
  ADD CONSTRAINT "Depot_position_check" CHECK (
    ("latitude" IS NULL AND "longitude" IS NULL)
    OR ("latitude" BETWEEN -90 AND 90 AND "longitude" BETWEEN -180 AND 180));

CREATE TABLE "Visit" (
  "id" UUID NOT NULL,
  "regionId" UUID NOT NULL,
  "responsableId" UUID NOT NULL,
  "targetKind" "LocationKind" NOT NULL,
  "targetId" UUID NOT NULL,
  "kind" "VisitKind" NOT NULL,
  "plannedStart" TIMESTAMP(3) NOT NULL,
  "plannedEnd" TIMESTAMP(3) NOT NULL,
  "day" DATE NOT NULL,
  "note" TEXT,
  "status" "VisitStatus" NOT NULL DEFAULT 'PLANNED',
  "unplanned" BOOLEAN NOT NULL DEFAULT false,
  "revision" INTEGER NOT NULL DEFAULT 0,
  "reminderSentAt" TIMESTAMP(3),
  "checkedInAt" TIMESTAMP(3),
  "checkedOutAt" TIMESTAMP(3),
  "cancelledAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "Visit_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "Visit_period_check" CHECK ("plannedEnd" > "plannedStart"),
  CONSTRAINT "Visit_note_check" CHECK ("note" IS NULL OR char_length("note") <= 500)
);
CREATE INDEX "Visit_responsableId_day_idx" ON "Visit"("responsableId", "day");
CREATE INDEX "Visit_regionId_day_idx" ON "Visit"("regionId", "day");
CREATE INDEX "Visit_status_plannedStart_idx" ON "Visit"("status", "plannedStart");

CREATE TABLE "VisitEvent" (
  "id" UUID NOT NULL,
  "visitId" UUID NOT NULL,
  "regionId" UUID NOT NULL,
  "responsableId" UUID NOT NULL,
  "kind" "VisitEventKind" NOT NULL,
  "occurredAt" TIMESTAMP(3) NOT NULL,
  "receivedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "latitude" DOUBLE PRECISION,
  "longitude" DOUBLE PRECISION,
  "accuracyM" DOUBLE PRECISION,
  "distanceM" INTEGER,
  "verdict" "PresenceVerdict" NOT NULL,
  "flags" TEXT[] DEFAULT ARRAY[]::TEXT[],
  "reason" TEXT,
  CONSTRAINT "VisitEvent_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "VisitEvent_position_check" CHECK (
    ("latitude" IS NULL AND "longitude" IS NULL)
    OR ("latitude" BETWEEN -90 AND 90 AND "longitude" BETWEEN -180 AND 180)),
  CONSTRAINT "VisitEvent_reason_check" CHECK ("reason" IS NULL OR char_length("reason") <= 300)
);
CREATE UNIQUE INDEX "VisitEvent_visitId_kind_key" ON "VisitEvent"("visitId", "kind");
CREATE INDEX "VisitEvent_responsableId_occurredAt_idx" ON "VisitEvent"("responsableId", "occurredAt");
CREATE INDEX "VisitEvent_receivedAt_idx" ON "VisitEvent"("receivedAt");
ALTER TABLE "VisitEvent" ADD CONSTRAINT "VisitEvent_visitId_fkey"
  FOREIGN KEY ("visitId") REFERENCES "Visit"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "CalendarFeed" (
  "userId" UUID NOT NULL,
  "token" TEXT NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "CalendarFeed_pkey" PRIMARY KEY ("userId"),
  CONSTRAINT "CalendarFeed_token_check" CHECK ("token" ~ '^[A-Za-z0-9_-]{43}$')
);
CREATE UNIQUE INDEX "CalendarFeed_token_key" ON "CalendarFeed"("token");

CREATE TABLE "PlanningPreference" (
  "userId" UUID NOT NULL,
  "leadMinutes" INTEGER NOT NULL DEFAULT 60,
  "eveningSummary" BOOLEAN NOT NULL DEFAULT true,
  CONSTRAINT "PlanningPreference_pkey" PRIMARY KEY ("userId"),
  CONSTRAINT "PlanningPreference_lead_check" CHECK ("leadMinutes" IN (0, 15, 30, 60, 120))
);

-- The evidence is append-only, and goes only after its 12 months (the visits that carry it too).
CREATE FUNCTION prevent_visit_event_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' AND OLD."receivedAt" < now() - interval '12 months' THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'History is append-only';
END; $$;
CREATE TRIGGER "VisitEvent_append_only" BEFORE UPDATE OR DELETE ON "VisitEvent"
  FOR EACH ROW EXECUTE FUNCTION prevent_visit_event_mutation();

-- Row-level security. A responsable sees and writes their own visits; the admin only reads them
-- (the test region stays hidden from them); trusted server work (SYSTEM) does the reminders.
ALTER TABLE "Visit" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "Visit" FORCE ROW LEVEL SECURITY;
CREATE POLICY "Visit_read" ON "Visit" FOR SELECT
  USING (app_admin_sees("regionId") OR "responsableId" = app_user());
CREATE POLICY "Visit_write" ON "Visit" FOR ALL
  USING (app_role() = 'SYSTEM' OR "responsableId" = app_user())
  WITH CHECK (app_role() = 'SYSTEM' OR "responsableId" = app_user());

ALTER TABLE "VisitEvent" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "VisitEvent" FORCE ROW LEVEL SECURITY;
CREATE POLICY "VisitEvent_read" ON "VisitEvent" FOR SELECT
  USING (app_admin_sees("regionId") OR "responsableId" = app_user());
CREATE POLICY "VisitEvent_write" ON "VisitEvent" FOR ALL
  USING (app_role() = 'SYSTEM' OR "responsableId" = app_user())
  WITH CHECK (app_role() = 'SYSTEM' OR "responsableId" = app_user());

ALTER TABLE "CalendarFeed" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "CalendarFeed" FORCE ROW LEVEL SECURITY;
CREATE POLICY "CalendarFeed_own" ON "CalendarFeed"
  USING (app_role() = 'SYSTEM' OR "userId" = app_user())
  WITH CHECK (app_role() = 'SYSTEM' OR "userId" = app_user());

ALTER TABLE "PlanningPreference" ENABLE ROW LEVEL SECURITY;
ALTER TABLE "PlanningPreference" FORCE ROW LEVEL SECURITY;
CREATE POLICY "PlanningPreference_own" ON "PlanningPreference"
  USING (app_role() = 'SYSTEM' OR "userId" = app_user())
  WITH CHECK (app_role() = 'SYSTEM' OR "userId" = app_user());
