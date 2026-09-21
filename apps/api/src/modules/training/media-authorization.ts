import { Prisma } from "@prisma/client";
import { requireRule } from "../../shared/domain/errors";

export async function requireImage(
  tx: Prisma.TransactionClient,
  id: string | null | undefined,
  purpose: "store" | "reward" | "catalog",
  storeId?: string,
) {
  if (!id) return;
  const media = await tx.mediaAsset.findUnique({ where: { id } });
  requireRule(
    media && media.purpose === purpose && media.storeId === (storeId ?? null),
    "MEDIA_SCOPE",
    "Cette image n’appartient pas à cet emplacement.",
    403,
  );
  requireRule(
    media.status === "ready" &&
      ["image/jpeg", "image/png"].includes(media.mime),
    "MEDIA_PROCESSING",
    "Attendez le traitement de cette image.",
  );
}
