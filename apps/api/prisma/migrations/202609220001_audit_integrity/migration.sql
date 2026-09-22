-- Additive resource controls; business histories and accepted operations are unchanged.
ALTER TABLE "MediaAsset" ADD COLUMN "storageBytes" BIGINT NOT NULL DEFAULT 0, ADD COLUMN "cleanedAt" TIMESTAMP(3);
UPDATE "MediaAsset" SET "storageBytes"=size+COALESCE("processedSize", CASE WHEN mime LIKE 'video/%' THEN 2147483648::bigint ELSE 16777216::bigint END);
ALTER TABLE "MediaAsset" ADD CHECK ("storageBytes">=0);
CREATE INDEX "MediaAsset_createdAt_cleanedAt_idx" ON "MediaAsset"("createdAt","cleanedAt");
CREATE INDEX "LoginAttempt_windowStart_idx" ON "LoginAttempt"("windowStart");
CREATE INDEX "DeviceToken_userId_id_idx" ON "DeviceToken"("userId",id);
CREATE TABLE "UploadChunk" ("mediaId" UUID NOT NULL REFERENCES "MediaAsset"(id), "offset" BIGINT NOT NULL, "length" INTEGER NOT NULL, "sha256" TEXT NOT NULL,
  PRIMARY KEY("mediaId","offset"), CHECK ("offset">=0 AND "length">0 AND "length"<=4194304), CHECK ("sha256" ~ '^[a-f0-9]{64}$'));
