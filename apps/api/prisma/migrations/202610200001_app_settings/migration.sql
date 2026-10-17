-- Settings the admin changes from the app (minimum version, working hours, who may choose a
-- grossiste), and one-time links that show a new administrator's authenticator QR code once.
CREATE TABLE "AppSetting" (
  "key"         TEXT PRIMARY KEY,
  "value"       JSONB NOT NULL,
  "updatedAt"   TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedById" UUID
);

CREATE TABLE "SetupLink" (
  "id"        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "tokenHash" TEXT NOT NULL UNIQUE,
  "userId"    UUID NOT NULL,
  -- The authenticator link (otpauth://…), encrypted like the secret it carries; erased once shown.
  "secret"    TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "usedAt"    TIMESTAMP(3)
);
CREATE INDEX "SetupLink_userId_idx" ON "SetupLink" ("userId");
