import { afterEach, describe, expect, it, vi } from "vitest";
import { Database } from "../src/shared/infrastructure/database";
const actor = {
  id: "internal-test",
  name: "Test",
  email: "test@example.test",
  platformAdmin: false,
};
const conflict = (code: string) =>
  Object.assign(new Error("TransactionWriteConflict"), {
    name: "DriverAdapterError",
    cause: { kind: "TransactionWriteConflict", originalCode: code },
  });
afterEach(() => vi.restoreAllMocks());
describe("bounded transaction recovery", () => {
  it.each(["40001", "40P01"])(
    "retries adapter commit failure %s",
    async (code) => {
      const db = new Database();
      const transaction = vi
        .spyOn(db, "$transaction")
        .mockRejectedValueOnce(conflict(code))
        .mockResolvedValueOnce("committed");
      try {
        expect(
          await db.scoped(actor, "org", "store", async () => "unused"),
        ).toBe("committed");
        expect(transaction).toHaveBeenCalledTimes(2);
      } finally {
        await db.$disconnect();
      }
    },
  );
  it("stops after four attempts with a recoverable result", async () => {
    const db = new Database();
    const transaction = vi
      .spyOn(db, "$transaction")
      .mockRejectedValue(conflict("40001"));
    try {
      await expect(
        db.scoped(actor, "org", "store", async () => true),
      ).rejects.toMatchObject({ code: "RETRY_LATER", status: 503 });
      expect(transaction).toHaveBeenCalledTimes(4);
    } finally {
      await db.$disconnect();
    }
  });
  it("does not retry unrelated database failures", async () => {
    const db = new Database(),
      failure = conflict("28P01");
    const transaction = vi.spyOn(db, "$transaction").mockRejectedValue(failure);
    try {
      await expect(
        db.scoped(actor, "org", "store", async () => true),
      ).rejects.toBe(failure);
      expect(transaction).toHaveBeenCalledTimes(1);
    } finally {
      await db.$disconnect();
    }
  });
});
