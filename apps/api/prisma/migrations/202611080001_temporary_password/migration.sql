-- A team member's account now starts with a generated password, sent by email and WhatsApp: the person
-- must replace it at the first sign-in, and it stops working after a week.
ALTER TABLE "User"
  ADD COLUMN "mustChangePassword" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "passwordExpiresAt" TIMESTAMP(3),
  ADD CONSTRAINT "User_temporary_password_check" CHECK (NOT "mustChangePassword" OR "passwordHash" IS NOT NULL);
