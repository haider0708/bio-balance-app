
-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateEnum
CREATE TYPE "Role" AS ENUM ('ADMIN', 'RESPONSABLE', 'GROSSISTE', 'VENDEUR');

-- CreateEnum
CREATE TYPE "Status" AS ENUM ('PENDING', 'ACTIVE', 'REJECTED', 'SUSPENDED');

-- CreateEnum
CREATE TYPE "Approval" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

-- CreateEnum
CREATE TYPE "LocationKind" AS ENUM ('PDV', 'DEPOT');

-- CreateEnum
CREATE TYPE "DeclarationKind" AS ENUM ('INITIAL', 'COUNT');

-- CreateEnum
CREATE TYPE "OrderStatus" AS ENUM ('REQUESTED', 'ASSIGNED', 'SHIPPED', 'RECEIVED', 'COMPLETED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "OrderSource" AS ENUM ('GROSSISTE', 'BIOBALANCE');

-- CreateEnum
CREATE TYPE "SaleStatus" AS ENUM ('ACTIVE', 'VOIDED');

-- CreateEnum
CREATE TYPE "RuleScope" AS ENUM ('PRODUCT', 'FAMILY');

-- CreateEnum
CREATE TYPE "WalletKind" AS ENUM ('SALE', 'CORRECTION', 'PAYOUT');

-- CreateEnum
CREATE TYPE "PayoutStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED');

-- CreateEnum
CREATE TYPE "MediaPurpose" AS ENUM ('PRODUCT', 'PROOF', 'TRAINING');

-- CreateEnum
CREATE TYPE "CourseStatus" AS ENUM ('DRAFT', 'PUBLISHED');

-- CreateEnum
CREATE TYPE "LessonKind" AS ENUM ('ARTICLE', 'VIDEO', 'PDF');

-- CreateTable
CREATE TABLE "Region" (
    "id" UUID NOT NULL,
    "code" TEXT NOT NULL,
    "name" TEXT NOT NULL,

    CONSTRAINT "Region_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "User" (
    "id" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "passwordHash" TEXT,
    "role" "Role" NOT NULL,
    "status" "Status" NOT NULL DEFAULT 'PENDING',
    "regionId" UUID,
    "pdvId" UUID,
    "locale" TEXT NOT NULL DEFAULT 'fr',
    "mfaSecret" TEXT,
    "lastTotpStep" BIGINT NOT NULL DEFAULT -1,
    "createdById" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedById" UUID,
    "decidedAt" TIMESTAMP(3),
    "decisionNote" TEXT,

    CONSTRAINT "User_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Session" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "revokedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Session_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AccessToken" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "purpose" TEXT NOT NULL,
    "tokenHash" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "usedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AccessToken_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LoginAttempt" (
    "key" TEXT NOT NULL,
    "count" INTEGER NOT NULL DEFAULT 0,
    "windowStart" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LoginAttempt_pkey" PRIMARY KEY ("key")
);

-- CreateTable
CREATE TABLE "Group" (
    "id" UUID NOT NULL,
    "regionId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "status" "Status" NOT NULL DEFAULT 'PENDING',
    "createdById" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedById" UUID,
    "decidedAt" TIMESTAMP(3),
    "decisionNote" TEXT,

    CONSTRAINT "Group_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Pdv" (
    "id" UUID NOT NULL,
    "regionId" UUID NOT NULL,
    "groupId" UUID,
    "name" TEXT NOT NULL,
    "address" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "phone" TEXT,
    "status" "Status" NOT NULL DEFAULT 'PENDING',
    "createdById" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedById" UUID,
    "decidedAt" TIMESTAMP(3),
    "decisionNote" TEXT,

    CONSTRAINT "Pdv_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Depot" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "address" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "phone" TEXT,
    "status" "Status" NOT NULL DEFAULT 'ACTIVE',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Depot_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Product" (
    "id" UUID NOT NULL,
    "reference" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "barcode" TEXT,
    "family" TEXT NOT NULL DEFAULT '',
    "range" TEXT NOT NULL DEFAULT '',
    "packageSize" TEXT NOT NULL DEFAULT '',
    "description" TEXT NOT NULL DEFAULT '',
    "instructions" TEXT NOT NULL DEFAULT '',
    "ingredients" TEXT NOT NULL DEFAULT '',
    "precautions" TEXT NOT NULL DEFAULT '',
    "imageId" UUID,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "Product_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Stock" (
    "locationId" UUID NOT NULL,
    "productId" UUID NOT NULL,
    "locationKind" "LocationKind" NOT NULL,
    "regionId" UUID,
    "quantity" INTEGER NOT NULL DEFAULT 0,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Stock_pkey" PRIMARY KEY ("locationId","productId")
);

-- CreateTable
CREATE TABLE "StockMovement" (
    "id" UUID NOT NULL,
    "locationId" UUID NOT NULL,
    "productId" UUID NOT NULL,
    "locationKind" "LocationKind" NOT NULL,
    "regionId" UUID,
    "delta" INTEGER NOT NULL,
    "reason" TEXT NOT NULL,
    "refType" TEXT NOT NULL,
    "refId" UUID NOT NULL,
    "actorId" UUID,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "StockMovement_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "StockDeclaration" (
    "id" UUID NOT NULL,
    "kind" "DeclarationKind" NOT NULL,
    "locationId" UUID NOT NULL,
    "locationKind" "LocationKind" NOT NULL,
    "regionId" UUID,
    "status" "Approval" NOT NULL DEFAULT 'PENDING',
    "photoId" UUID NOT NULL,
    "note" TEXT,
    "createdById" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedById" UUID,
    "decidedAt" TIMESTAMP(3),
    "decisionNote" TEXT,

    CONSTRAINT "StockDeclaration_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "StockDeclarationLine" (
    "id" UUID NOT NULL,
    "declarationId" UUID NOT NULL,
    "productId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "approvedQuantity" INTEGER,

    CONSTRAINT "StockDeclarationLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RestockOrder" (
    "id" UUID NOT NULL,
    "number" TEXT NOT NULL,
    "regionId" UUID,
    "destKind" "LocationKind" NOT NULL,
    "destId" UUID NOT NULL,
    "status" "OrderStatus" NOT NULL DEFAULT 'REQUESTED',
    "source" "OrderSource",
    "supplierDepotId" UUID,
    "requestedById" UUID NOT NULL,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "assignedAt" TIMESTAMP(3),
    "shippedAt" TIMESTAMP(3),
    "receiverId" UUID,
    "receiptPhotoId" UUID,
    "receivedAt" TIMESTAMP(3),
    "decidedById" UUID,
    "decidedAt" TIMESTAMP(3),
    "decisionNote" TEXT,
    "cancelReason" TEXT,

    CONSTRAINT "RestockOrder_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RestockLine" (
    "id" UUID NOT NULL,
    "orderId" UUID NOT NULL,
    "productId" UUID NOT NULL,
    "requested" INTEGER NOT NULL,
    "shipped" INTEGER,
    "received" INTEGER,
    "approved" INTEGER,

    CONSTRAINT "RestockLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Sale" (
    "id" UUID NOT NULL,
    "pdvId" UUID NOT NULL,
    "regionId" UUID NOT NULL,
    "sellerId" UUID NOT NULL,
    "occurredAt" TIMESTAMP(3) NOT NULL,
    "day" DATE NOT NULL,
    "units" INTEGER NOT NULL,
    "rewardMillimes" BIGINT NOT NULL DEFAULT 0,
    "status" "SaleStatus" NOT NULL DEFAULT 'ACTIVE',
    "version" INTEGER NOT NULL DEFAULT 1,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Sale_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SaleLine" (
    "id" UUID NOT NULL,
    "saleId" UUID NOT NULL,
    "productId" UUID NOT NULL,
    "quantity" INTEGER NOT NULL,
    "unitRewardMillimes" BIGINT NOT NULL DEFAULT 0,

    CONSTRAINT "SaleLine_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "SaleRevision" (
    "id" UUID NOT NULL,
    "saleId" UUID NOT NULL,
    "version" INTEGER NOT NULL,
    "editorId" UUID NOT NULL,
    "reason" TEXT NOT NULL,
    "before" JSONB NOT NULL,
    "after" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SaleRevision_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "RewardRule" (
    "id" UUID NOT NULL,
    "scope" "RuleScope" NOT NULL,
    "productId" UUID,
    "family" TEXT,
    "targetKey" TEXT NOT NULL,
    "amountMillimes" BIGINT NOT NULL,
    "startsOn" DATE NOT NULL,
    "endsOn" DATE,
    "note" TEXT,
    "createdById" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "cancelledAt" TIMESTAMP(3),
    "cancelledById" UUID,

    CONSTRAINT "RewardRule_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "WalletEntry" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "kind" "WalletKind" NOT NULL,
    "amountMillimes" BIGINT NOT NULL,
    "saleId" UUID,
    "payoutId" UUID,
    "note" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WalletEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "PayoutRequest" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "regionId" UUID NOT NULL,
    "amountMillimes" BIGINT NOT NULL,
    "status" "PayoutStatus" NOT NULL DEFAULT 'PENDING',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "decidedById" UUID,
    "decidedAt" TIMESTAMP(3),
    "decisionNote" TEXT,
    "paidAt" TIMESTAMP(3),
    "reference" TEXT,

    CONSTRAINT "PayoutRequest_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Message" (
    "id" UUID NOT NULL,
    "authorId" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "audience" JSONB NOT NULL,
    "pinned" BOOLEAN NOT NULL DEFAULT false,
    "scheduledFor" TIMESTAMP(3),
    "sentAt" TIMESTAMP(3),
    "recipientCount" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Message_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Notification" (
    "id" UUID NOT NULL,
    "userId" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "messageId" UUID,
    "key" TEXT,
    "params" JSONB,
    "title" TEXT,
    "body" TEXT,
    "pinned" BOOLEAN NOT NULL DEFAULT false,
    "entityType" TEXT,
    "entityId" UUID,
    "readAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Notification_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Course" (
    "id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "summary" TEXT NOT NULL DEFAULT '',
    "coverId" UUID,
    "status" "CourseStatus" NOT NULL DEFAULT 'DRAFT',
    "audience" JSONB NOT NULL,
    "position" INTEGER NOT NULL DEFAULT 0,
    "createdById" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "publishedAt" TIMESTAMP(3),

    CONSTRAINT "Course_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Lesson" (
    "id" UUID NOT NULL,
    "courseId" UUID NOT NULL,
    "position" INTEGER NOT NULL,
    "title" TEXT NOT NULL,
    "kind" "LessonKind" NOT NULL,
    "body" TEXT NOT NULL DEFAULT '',
    "mediaId" UUID,
    "videoUrl" TEXT,
    "minutes" INTEGER,

    CONSTRAINT "Lesson_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "LessonProgress" (
    "userId" UUID NOT NULL,
    "lessonId" UUID NOT NULL,
    "completedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "LessonProgress_pkey" PRIMARY KEY ("userId","lessonId")
);

-- CreateTable
CREATE TABLE "MediaAsset" (
    "id" UUID NOT NULL,
    "ownerId" UUID NOT NULL,
    "purpose" "MediaPurpose" NOT NULL,
    "regionId" UUID,
    "fileName" TEXT NOT NULL,
    "mime" TEXT NOT NULL,
    "size" BIGINT NOT NULL,
    "sha256" TEXT NOT NULL,
    "path" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "MediaAsset_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "AuditEntry" (
    "id" UUID NOT NULL,
    "actorId" UUID,
    "action" TEXT NOT NULL,
    "entity" TEXT NOT NULL,
    "entityId" TEXT NOT NULL,
    "regionId" UUID,
    "details" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "AuditEntry_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Job" (
    "id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "payload" JSONB NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "availableAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "lockedAt" TIMESTAMP(3),
    "leaseToken" UUID,
    "lastError" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Job_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Region_code_key" ON "Region"("code");

-- CreateIndex
CREATE UNIQUE INDEX "User_email_key" ON "User"("email");

-- CreateIndex
CREATE INDEX "User_role_status_idx" ON "User"("role", "status");

-- CreateIndex
CREATE INDEX "User_regionId_role_status_idx" ON "User"("regionId", "role", "status");

-- CreateIndex
CREATE INDEX "User_pdvId_idx" ON "User"("pdvId");

-- CreateIndex
CREATE UNIQUE INDEX "Session_tokenHash_key" ON "Session"("tokenHash");

-- CreateIndex
CREATE INDEX "Session_userId_idx" ON "Session"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "AccessToken_tokenHash_key" ON "AccessToken"("tokenHash");

-- CreateIndex
CREATE INDEX "AccessToken_userId_purpose_idx" ON "AccessToken"("userId", "purpose");

-- CreateIndex
CREATE INDEX "LoginAttempt_windowStart_idx" ON "LoginAttempt"("windowStart");

-- CreateIndex
CREATE INDEX "Group_regionId_status_idx" ON "Group"("regionId", "status");

-- CreateIndex
CREATE INDEX "Pdv_regionId_status_idx" ON "Pdv"("regionId", "status");

-- CreateIndex
CREATE INDEX "Pdv_groupId_idx" ON "Pdv"("groupId");

-- CreateIndex
CREATE UNIQUE INDEX "Depot_userId_key" ON "Depot"("userId");

-- CreateIndex
CREATE UNIQUE INDEX "Product_reference_key" ON "Product"("reference");

-- CreateIndex
CREATE UNIQUE INDEX "Product_barcode_key" ON "Product"("barcode");

-- CreateIndex
CREATE INDEX "Product_family_idx" ON "Product"("family");

-- CreateIndex
CREATE INDEX "Product_active_name_idx" ON "Product"("active", "name");

-- CreateIndex
CREATE INDEX "Stock_regionId_idx" ON "Stock"("regionId");

-- CreateIndex
CREATE INDEX "StockMovement_locationId_productId_createdAt_idx" ON "StockMovement"("locationId", "productId", "createdAt");

-- CreateIndex
CREATE INDEX "StockMovement_refType_refId_idx" ON "StockMovement"("refType", "refId");

-- CreateIndex
CREATE INDEX "StockDeclaration_status_createdAt_idx" ON "StockDeclaration"("status", "createdAt");

-- CreateIndex
CREATE INDEX "StockDeclaration_locationId_status_idx" ON "StockDeclaration"("locationId", "status");

-- CreateIndex
CREATE INDEX "StockDeclaration_regionId_status_idx" ON "StockDeclaration"("regionId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "StockDeclarationLine_declarationId_productId_key" ON "StockDeclarationLine"("declarationId", "productId");

-- CreateIndex
CREATE UNIQUE INDEX "RestockOrder_number_key" ON "RestockOrder"("number");

-- CreateIndex
CREATE INDEX "RestockOrder_status_createdAt_idx" ON "RestockOrder"("status", "createdAt");

-- CreateIndex
CREATE INDEX "RestockOrder_regionId_status_idx" ON "RestockOrder"("regionId", "status");

-- CreateIndex
CREATE INDEX "RestockOrder_supplierDepotId_status_idx" ON "RestockOrder"("supplierDepotId", "status");

-- CreateIndex
CREATE INDEX "RestockOrder_destId_status_idx" ON "RestockOrder"("destId", "status");

-- CreateIndex
CREATE UNIQUE INDEX "RestockLine_orderId_productId_key" ON "RestockLine"("orderId", "productId");

-- CreateIndex
CREATE INDEX "Sale_pdvId_occurredAt_idx" ON "Sale"("pdvId", "occurredAt");

-- CreateIndex
CREATE INDEX "Sale_regionId_day_idx" ON "Sale"("regionId", "day");

-- CreateIndex
CREATE INDEX "Sale_sellerId_occurredAt_idx" ON "Sale"("sellerId", "occurredAt");

-- CreateIndex
CREATE INDEX "Sale_day_idx" ON "Sale"("day");

-- CreateIndex
CREATE INDEX "SaleLine_productId_idx" ON "SaleLine"("productId");

-- CreateIndex
CREATE UNIQUE INDEX "SaleLine_saleId_productId_key" ON "SaleLine"("saleId", "productId");

-- CreateIndex
CREATE UNIQUE INDEX "SaleRevision_saleId_version_key" ON "SaleRevision"("saleId", "version");

-- CreateIndex
CREATE INDEX "RewardRule_targetKey_startsOn_idx" ON "RewardRule"("targetKey", "startsOn");

-- CreateIndex
CREATE INDEX "WalletEntry_userId_createdAt_idx" ON "WalletEntry"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "PayoutRequest_status_createdAt_idx" ON "PayoutRequest"("status", "createdAt");

-- CreateIndex
CREATE INDEX "PayoutRequest_userId_status_idx" ON "PayoutRequest"("userId", "status");

-- CreateIndex
CREATE INDEX "Message_createdAt_idx" ON "Message"("createdAt");

-- CreateIndex
CREATE INDEX "Notification_userId_createdAt_idx" ON "Notification"("userId", "createdAt");

-- CreateIndex
CREATE INDEX "Notification_userId_readAt_idx" ON "Notification"("userId", "readAt");

-- CreateIndex
CREATE INDEX "Notification_messageId_idx" ON "Notification"("messageId");

-- CreateIndex
CREATE UNIQUE INDEX "Notification_userId_messageId_key" ON "Notification"("userId", "messageId");

-- CreateIndex
CREATE INDEX "Course_status_position_idx" ON "Course"("status", "position");

-- CreateIndex
CREATE INDEX "Lesson_courseId_position_idx" ON "Lesson"("courseId", "position");

-- CreateIndex
CREATE INDEX "LessonProgress_lessonId_idx" ON "LessonProgress"("lessonId");

-- CreateIndex
CREATE INDEX "MediaAsset_ownerId_idx" ON "MediaAsset"("ownerId");

-- CreateIndex
CREATE INDEX "AuditEntry_entity_entityId_idx" ON "AuditEntry"("entity", "entityId");

-- CreateIndex
CREATE INDEX "AuditEntry_createdAt_idx" ON "AuditEntry"("createdAt");

-- CreateIndex
CREATE INDEX "AuditEntry_regionId_createdAt_idx" ON "AuditEntry"("regionId", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "Job_key_key" ON "Job"("key");

-- CreateIndex
CREATE INDEX "Job_status_availableAt_idx" ON "Job"("status", "availableAt");

-- AddForeignKey
ALTER TABLE "StockDeclarationLine" ADD CONSTRAINT "StockDeclarationLine_declarationId_fkey" FOREIGN KEY ("declarationId") REFERENCES "StockDeclaration"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "RestockLine" ADD CONSTRAINT "RestockLine_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "RestockOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "SaleLine" ADD CONSTRAINT "SaleLine_saleId_fkey" FOREIGN KEY ("saleId") REFERENCES "Sale"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Lesson" ADD CONSTRAINT "Lesson_courseId_fkey" FOREIGN KEY ("courseId") REFERENCES "Course"("id") ON DELETE CASCADE ON UPDATE CASCADE;


-- ═════════════════════════ Fixed data ═════════════════════════
INSERT INTO "Region" (id, code, name) VALUES
  (gen_random_uuid(), 'NORD', 'Nord'),
  (gen_random_uuid(), 'CENTRE', 'Centre'),
  (gen_random_uuid(), 'SUD', 'Sud');

-- ═════════════════════════ Integrity ═════════════════════════
ALTER TABLE "User" ADD CONSTRAINT "User_region_fk" FOREIGN KEY ("regionId") REFERENCES "Region"(id);
ALTER TABLE "User" ADD CONSTRAINT "User_pdv_fk" FOREIGN KEY ("pdvId") REFERENCES "Pdv"(id);
ALTER TABLE "User" ADD CONSTRAINT "User_scope_check" CHECK (
  (role IN ('RESPONSABLE','VENDEUR')) = ("regionId" IS NOT NULL)
  AND (role = 'VENDEUR') = ("pdvId" IS NOT NULL));
-- One responsable per region.
CREATE UNIQUE INDEX "User_one_responsable_per_region" ON "User"("regionId")
  WHERE role = 'RESPONSABLE' AND status IN ('PENDING','ACTIVE');
ALTER TABLE "Session" ADD CONSTRAINT "Session_user_fk" FOREIGN KEY ("userId") REFERENCES "User"(id) ON DELETE CASCADE;
ALTER TABLE "AccessToken" ADD CONSTRAINT "AccessToken_user_fk" FOREIGN KEY ("userId") REFERENCES "User"(id) ON DELETE CASCADE;
ALTER TABLE "Group" ADD CONSTRAINT "Group_region_fk" FOREIGN KEY ("regionId") REFERENCES "Region"(id);
ALTER TABLE "Pdv" ADD CONSTRAINT "Pdv_region_fk" FOREIGN KEY ("regionId") REFERENCES "Region"(id);
ALTER TABLE "Pdv" ADD CONSTRAINT "Pdv_group_fk" FOREIGN KEY ("groupId") REFERENCES "Group"(id);
ALTER TABLE "Depot" ADD CONSTRAINT "Depot_user_fk" FOREIGN KEY ("userId") REFERENCES "User"(id);
ALTER TABLE "Product" ADD CONSTRAINT "Product_image_fk" FOREIGN KEY ("imageId") REFERENCES "MediaAsset"(id);
ALTER TABLE "MediaAsset" ADD CONSTRAINT "MediaAsset_owner_fk" FOREIGN KEY ("ownerId") REFERENCES "User"(id);
ALTER TABLE "Stock" ADD CONSTRAINT "Stock_product_fk" FOREIGN KEY ("productId") REFERENCES "Product"(id);
ALTER TABLE "StockMovement" ADD CONSTRAINT "StockMovement_product_fk" FOREIGN KEY ("productId") REFERENCES "Product"(id);
ALTER TABLE "StockDeclaration" ADD CONSTRAINT "StockDeclaration_photo_fk" FOREIGN KEY ("photoId") REFERENCES "MediaAsset"(id);
ALTER TABLE "StockDeclarationLine" ADD CONSTRAINT "StockDeclarationLine_product_fk" FOREIGN KEY ("productId") REFERENCES "Product"(id);
ALTER TABLE "StockDeclarationLine" ADD CONSTRAINT "StockDeclarationLine_qty" CHECK (quantity >= 0 AND ("approvedQuantity" IS NULL OR "approvedQuantity" >= 0));
-- At most one declaration waits for the admin per place.
CREATE UNIQUE INDEX "StockDeclaration_one_pending" ON "StockDeclaration"("locationId") WHERE status = 'PENDING';
ALTER TABLE "RestockOrder" ADD CONSTRAINT "RestockOrder_photo_fk" FOREIGN KEY ("receiptPhotoId") REFERENCES "MediaAsset"(id);
ALTER TABLE "RestockLine" ADD CONSTRAINT "RestockLine_product_fk" FOREIGN KEY ("productId") REFERENCES "Product"(id);
ALTER TABLE "RestockLine" ADD CONSTRAINT "RestockLine_qty" CHECK (requested > 0
  AND (shipped IS NULL OR shipped >= 0) AND (received IS NULL OR received >= 0) AND (approved IS NULL OR approved >= 0));
CREATE SEQUENCE "restock_number_seq";
ALTER TABLE "Sale" ADD CONSTRAINT "Sale_pdv_fk" FOREIGN KEY ("pdvId") REFERENCES "Pdv"(id);
ALTER TABLE "Sale" ADD CONSTRAINT "Sale_seller_fk" FOREIGN KEY ("sellerId") REFERENCES "User"(id);
ALTER TABLE "SaleLine" ADD CONSTRAINT "SaleLine_product_fk" FOREIGN KEY ("productId") REFERENCES "Product"(id);
ALTER TABLE "SaleLine" ADD CONSTRAINT "SaleLine_qty" CHECK (quantity > 0 AND "unitRewardMillimes" >= 0);
ALTER TABLE "RewardRule" ADD CONSTRAINT "RewardRule_product_fk" FOREIGN KEY ("productId") REFERENCES "Product"(id);
ALTER TABLE "RewardRule" ADD CONSTRAINT "RewardRule_shape" CHECK (
  "amountMillimes" >= 0 AND ("endsOn" IS NULL OR "endsOn" >= "startsOn")
  AND ((scope = 'PRODUCT' AND "productId" IS NOT NULL AND family IS NULL)
    OR (scope = 'FAMILY' AND family IS NOT NULL AND "productId" IS NULL)));
-- Two live rules for the same product or family can never cover the same day.
CREATE EXTENSION IF NOT EXISTS btree_gist;
ALTER TABLE "RewardRule" ADD CONSTRAINT "RewardRule_no_overlap" EXCLUDE USING gist
  ("targetKey" WITH =, daterange("startsOn", "endsOn", '[]') WITH &&) WHERE ("cancelledAt" IS NULL);
ALTER TABLE "WalletEntry" ADD CONSTRAINT "WalletEntry_user_fk" FOREIGN KEY ("userId") REFERENCES "User"(id);
ALTER TABLE "PayoutRequest" ADD CONSTRAINT "PayoutRequest_user_fk" FOREIGN KEY ("userId") REFERENCES "User"(id);
ALTER TABLE "PayoutRequest" ADD CONSTRAINT "PayoutRequest_amount" CHECK ("amountMillimes" > 0);
ALTER TABLE "Notification" ADD CONSTRAINT "Notification_user_fk" FOREIGN KEY ("userId") REFERENCES "User"(id) ON DELETE CASCADE;
ALTER TABLE "Notification" ADD CONSTRAINT "Notification_message_fk" FOREIGN KEY ("messageId") REFERENCES "Message"(id);
ALTER TABLE "Lesson" ADD CONSTRAINT "Lesson_media_fk" FOREIGN KEY ("mediaId") REFERENCES "MediaAsset"(id);
ALTER TABLE "LessonProgress" ADD CONSTRAINT "LessonProgress_user_fk" FOREIGN KEY ("userId") REFERENCES "User"(id) ON DELETE CASCADE;
ALTER TABLE "LessonProgress" ADD CONSTRAINT "LessonProgress_lesson_fk" FOREIGN KEY ("lessonId") REFERENCES "Lesson"(id) ON DELETE CASCADE;

-- ═════════════════════════ Append-only history ═════════════════════════
CREATE FUNCTION prevent_history_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'History is append-only'; END; $$;
CREATE TRIGGER "StockMovement_append_only" BEFORE UPDATE OR DELETE ON "StockMovement" FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();
CREATE TRIGGER "SaleRevision_append_only" BEFORE UPDATE OR DELETE ON "SaleRevision" FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();
CREATE TRIGGER "WalletEntry_append_only" BEFORE UPDATE OR DELETE ON "WalletEntry" FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();
CREATE TRIGGER "AuditEntry_append_only" BEFORE UPDATE OR DELETE ON "AuditEntry" FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();

-- ═════════════════════════ Row-level security ═════════════════════════
-- The API sets app.role, app.user_id, app.region_id, app.pdv_id and app.depot_id
-- inside every transaction. The application database role cannot bypass these
-- policies, so one region can never read or change another region's data, even
-- if a query forgets its own filter.
CREATE FUNCTION app_role() RETURNS text LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.role', true), '') $$;
CREATE FUNCTION app_user() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.user_id', true), '')::uuid $$;
CREATE FUNCTION app_region() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.region_id', true), '')::uuid $$;
CREATE FUNCTION app_pdv() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.pdv_id', true), '')::uuid $$;
CREATE FUNCTION app_depot() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.depot_id', true), '')::uuid $$;
/** The admin, and trusted server jobs such as notification delivery. */
CREATE FUNCTION app_is_admin() RETURNS boolean LANGUAGE sql STABLE AS $$ SELECT app_role() IN ('ADMIN','SYSTEM') $$;
CREATE FUNCTION app_in_region(region uuid) RETURNS boolean LANGUAGE sql STABLE AS
  $$ SELECT app_role() = 'RESPONSABLE' AND region IS NOT NULL AND region = app_region() $$;

DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['Group','Pdv','Depot','Stock','StockMovement','StockDeclaration','StockDeclarationLine',
    'RestockOrder','RestockLine','Sale','SaleLine','SaleRevision','RewardRule','WalletEntry','PayoutRequest',
    'Notification','AuditEntry','MediaAsset'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

CREATE POLICY "Group_rls" ON "Group" USING (app_is_admin() OR app_in_region("regionId"))
  WITH CHECK (app_is_admin() OR app_in_region("regionId"));
CREATE POLICY "Pdv_rls" ON "Pdv" USING (app_is_admin() OR app_in_region("regionId") OR id = app_pdv())
  WITH CHECK (app_is_admin() OR app_in_region("regionId"));
-- Depots: responsables may look (to call the grossiste); only the admin changes them.
CREATE POLICY "Depot_read" ON "Depot" FOR SELECT USING (app_is_admin() OR app_role() = 'RESPONSABLE' OR "userId" = app_user());
CREATE POLICY "Depot_write" ON "Depot" FOR ALL USING (app_is_admin()) WITH CHECK (app_is_admin());

CREATE POLICY "Stock_rls" ON "Stock" USING (app_is_admin() OR app_in_region("regionId") OR "locationId" = app_depot()
  OR ("locationKind" = 'PDV' AND "locationId" = app_pdv()))
  WITH CHECK (app_is_admin() OR app_in_region("regionId") OR "locationId" = app_depot()
  OR ("locationKind" = 'PDV' AND "locationId" = app_pdv()));
CREATE POLICY "StockMovement_rls" ON "StockMovement" USING (app_is_admin() OR app_in_region("regionId") OR "locationId" = app_depot())
  WITH CHECK (app_is_admin() OR app_in_region("regionId") OR "locationId" = app_depot()
  OR ("locationKind" = 'PDV' AND "locationId" = app_pdv()));
CREATE POLICY "StockDeclaration_rls" ON "StockDeclaration" USING (app_is_admin() OR app_in_region("regionId") OR "locationId" = app_depot())
  WITH CHECK (app_is_admin() OR app_in_region("regionId") OR "locationId" = app_depot());
CREATE POLICY "StockDeclarationLine_rls" ON "StockDeclarationLine"
  USING (EXISTS (SELECT 1 FROM "StockDeclaration" d WHERE d.id = "declarationId"))
  WITH CHECK (EXISTS (SELECT 1 FROM "StockDeclaration" d WHERE d.id = "declarationId"));

CREATE FUNCTION app_sees_order(region uuid, supplier uuid, kind "LocationKind", dest uuid, receiver uuid)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT app_is_admin() OR app_in_region(region)
    OR (app_role() = 'GROSSISTE' AND app_depot() IS NOT NULL AND (supplier = app_depot() OR (kind = 'DEPOT' AND dest = app_depot())))
    OR (receiver IS NOT NULL AND receiver = app_user()) $$;
CREATE POLICY "RestockOrder_rls" ON "RestockOrder"
  USING (app_sees_order("regionId", "supplierDepotId", "destKind", "destId", "receiverId"))
  WITH CHECK (app_sees_order("regionId", "supplierDepotId", "destKind", "destId", "receiverId"));
CREATE POLICY "RestockLine_rls" ON "RestockLine"
  USING (EXISTS (SELECT 1 FROM "RestockOrder" o WHERE o.id = "orderId"))
  WITH CHECK (EXISTS (SELECT 1 FROM "RestockOrder" o WHERE o.id = "orderId"));

CREATE FUNCTION app_sees_sale(region uuid, seller uuid, pdv uuid) RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT app_is_admin() OR app_in_region(region)
    OR (app_role() = 'VENDEUR' AND seller = app_user() AND pdv = app_pdv()) $$;
CREATE POLICY "Sale_rls" ON "Sale" USING (app_sees_sale("regionId", "sellerId", "pdvId"))
  WITH CHECK (app_sees_sale("regionId", "sellerId", "pdvId"));
CREATE POLICY "SaleLine_rls" ON "SaleLine"
  USING (EXISTS (SELECT 1 FROM "Sale" s WHERE s.id = "saleId"))
  WITH CHECK (EXISTS (SELECT 1 FROM "Sale" s WHERE s.id = "saleId"));
CREATE POLICY "SaleRevision_rls" ON "SaleRevision"
  USING (EXISTS (SELECT 1 FROM "Sale" s WHERE s.id = "saleId"))
  WITH CHECK (EXISTS (SELECT 1 FROM "Sale" s WHERE s.id = "saleId"));

-- Everyone who sells must read the rules to price a sale; only the admin writes them.
CREATE POLICY "RewardRule_read" ON "RewardRule" FOR SELECT USING (true);
CREATE POLICY "RewardRule_write" ON "RewardRule" FOR ALL USING (app_is_admin()) WITH CHECK (app_is_admin());

-- A wallet belongs to its owner; the entries a sale correction creates follow that sale.
CREATE POLICY "WalletEntry_rls" ON "WalletEntry"
  USING (app_is_admin() OR "userId" = app_user()
    OR ("saleId" IS NOT NULL AND EXISTS (SELECT 1 FROM "Sale" s WHERE s.id = "saleId")))
  WITH CHECK (app_is_admin() OR "userId" = app_user()
    OR ("saleId" IS NOT NULL AND EXISTS (SELECT 1 FROM "Sale" s WHERE s.id = "saleId")));
CREATE POLICY "PayoutRequest_rls" ON "PayoutRequest" USING (app_is_admin() OR "userId" = app_user())
  WITH CHECK (app_is_admin() OR "userId" = app_user());

-- Anyone can notify anyone, but each person reads only their own inbox.
CREATE POLICY "Notification_insert" ON "Notification" FOR INSERT WITH CHECK (true);
CREATE POLICY "Notification_own" ON "Notification" FOR SELECT USING (app_is_admin() OR "userId" = app_user());
CREATE POLICY "Notification_update" ON "Notification" FOR UPDATE USING (app_is_admin() OR "userId" = app_user());
CREATE POLICY "Notification_delete" ON "Notification" FOR DELETE USING (app_is_admin() OR "userId" = app_user());

CREATE POLICY "AuditEntry_insert" ON "AuditEntry" FOR INSERT WITH CHECK (true);
CREATE POLICY "AuditEntry_read" ON "AuditEntry" FOR SELECT USING (app_is_admin());

-- Proof photos are private to their author, the admin and the region's responsable.
CREATE POLICY "MediaAsset_insert" ON "MediaAsset" FOR INSERT WITH CHECK ("ownerId" = app_user() OR app_is_admin());
CREATE POLICY "MediaAsset_read" ON "MediaAsset" FOR SELECT USING (
  purpose <> 'PROOF' OR app_is_admin() OR "ownerId" = app_user() OR app_in_region("regionId"));
CREATE POLICY "MediaAsset_admin_write" ON "MediaAsset" FOR UPDATE USING (app_is_admin()) WITH CHECK (app_is_admin());
