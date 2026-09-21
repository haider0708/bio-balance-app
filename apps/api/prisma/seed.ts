import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { randomBytes } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import * as argon2 from "argon2";
import { encryptSecret } from "../src/modules/identity/identity.service";
import { Secret, TOTP } from "otpauth";
import { lotIdentity } from "../src/modules/operations/infrastructure/prisma-ledger";
if (process.env.NODE_ENV === "production")
  throw new Error("Development seed is disabled in production.");
process.loadEnvFile(".env");
const db = new PrismaClient({
  adapter: new PrismaPg({
    connectionString:
      process.env.SEED_DATABASE_URL ??
      "postgresql://biobalance:local-development-only@localhost:54329/biobalance",
  }),
});
const id = (n: number) =>
  `b10ba1a0-0000-4000-8000-${n.toString().padStart(12, "0")}`;
async function seed() {
  const secretFile = "../../.local-credentials.json";
  const credentials = existsSync(secretFile)
    ? JSON.parse(readFileSync(secretFile, "utf8"))
    : {
        password: randomBytes(18).toString("base64url"),
        adminSecret: randomBytes(20).toString("hex"),
      };
  credentials.manager = "responsable@example.test";
  credentials.seller = "vendeur@example.test";
  credentials.admin = "admin@example.test";
  credentials.adminOtpAuth = new TOTP({
    issuer: "BioBalance Local",
    label: credentials.admin,
    secret: Secret.fromHex(credentials.adminSecret),
  }).toString();
  writeFileSync(secretFile, JSON.stringify(credentials, null, 2) + "\n", {
    mode: 0o600,
  });
  const hash = await argon2.hash(credentials.password, {
    type: argon2.argon2id,
  });
  await db.organization.upsert({
    where: { id: id(1) },
    create: { id: id(1), name: "Partenaire de démonstration" },
    update: {},
  });
  await db.store.upsert({
    where: { id: id(2) },
    create: {
      id: id(2),
      organizationId: id(1),
      name: "BioBalance · Démonstration",
      address: "Adresse de démonstration",
      city: "Tunis",
      onboardingStep: 2,
    },
    update: {},
  });
  for (const [n, email, name, admin] of [
    [3, credentials.manager, "Amira", false],
    [4, credentials.seller, "Yasmine", false],
    [5, credentials.admin, "BioBalance", true],
  ] as const) {
    await db.user.upsert({
      where: { id: id(n) },
      create: {
        id: id(n),
        email,
        name,
        passwordHash: hash,
        platformAdmin: admin,
        mfaSecret: admin ? encryptSecret(credentials.adminSecret) : null,
      },
      update: {},
    });
    await db.membership.upsert({
      where: { storeId_userId: { storeId: id(2), userId: id(n) } },
      create: {
        organizationId: id(1),
        storeId: id(2),
        userId: id(n),
        permissions:
          n === 4 ? ["sell", "receive"] : ["manage", "sell", "receive"],
      },
      update: {},
    });
  }
  await db.organizationMembership.upsert({
    where: { organizationId_userId: { organizationId: id(1), userId: id(3) } },
    create: { organizationId: id(1), userId: id(3) },
    update: {},
  });
  for (const [n, name, ref, quantity, price, points] of [
    [10, "Sérum PDRN", "DEMO-PDRN", 24, 89900, 20],
    [11, "Crème hydratante", "DEMO-HYDRA", 4, 49900, 10],
    [12, "Gel nettoyant", "DEMO-CLEAN", 16, 32900, 8],
  ] as const) {
    await db.product.upsert({
      where: { id: id(n) },
      create: {
        id: id(n),
        name,
        reference: ref,
        barcode: `61900000000${n}`,
        description:
          "Produit de démonstration. Remplacer par le catalogue officiel avant lancement.",
      },
      update: {},
    });
    await db.storeProduct.upsert({
      where: { storeId_productId: { storeId: id(2), productId: id(n) } },
      create: {
        organizationId: id(1),
        storeId: id(2),
        productId: id(n),
        priceMillimes: BigInt(price),
        threshold: 5,
        pointsPerUnit: points,
        pointsConfigured: true,
      },
      update: {},
    });
    const lotId = lotIdentity(id(2), id(n), "DEMO-2026", "2027-12-31");
    if (!(await db.inventoryLot.findUnique({ where: { id: lotId } }))) {
      await db.$transaction(async (tx) => {
        await tx.inventoryLot.create({
          data: {
            id: lotId,
            organizationId: id(1),
            storeId: id(2),
            productId: id(n),
            batch: "DEMO-2026",
            expiry: new Date("2027-12-31"),
            sellable: quantity,
          },
        });
        await tx.stockMovement.create({
          data: {
            organizationId: id(1),
            storeId: id(2),
            lotId,
            quantity,
            reason: "opening",
            sourceId: lotId,
            actorId: id(3),
            operationId: lotId,
          },
        });
      });
    }
  }
  await db.reward.upsert({
    where: { id: id(20) },
    create: {
      id: id(20),
      organizationId: id(1),
      storeId: id(2),
      title: "Votre crème hydratante offerte",
      description: "Un cadeau pour récompenser vos conseils.",
      cost: 200,
      productId: id(11),
      quantity: 1,
    },
    update: {},
  });
  await db.trainingContent.upsert({
    where: { id: id(30) },
    create: {
      id: id(30),
      title: "Bien accueillir et conseiller votre client",
      body: "<p>Écoutez les besoins du client, posez des questions simples et présentez les caractéristiques validées du produit.</p><p>Ce contenu est un exemple destiné à la démonstration.</p>",
      type: "article",
      status: "published",
      productIds: [],
      authorId: id(5),
    },
    update: {},
  });
  console.log(
    "Development data ready. Credentials saved privately to .local-credentials.json.",
  );
  await db.$disconnect();
}
void seed();
