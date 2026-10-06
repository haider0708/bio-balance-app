import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  client,
  createAccount,
  fakeJpeg,
  resetDatabase,
  startApi,
  type Api,
} from "./helpers";
import { buildWorld, type World } from "./world";

let api: Api;
let w: World;
beforeAll(async () => {
  api = await startApi();
});
afterAll(() => api.close());
beforeEach(async () => {
  await resetDatabase();
  w = await buildWorld(api);
});

describe("catalog", () => {
  it("lets the admin create, change and hide products", async () => {
    const created = await w.a.post("/v1/products", {
      reference: "NEW-1",
      name: "New cream",
      family: "Creams",
      barcode: "1234567890123",
      imageId: null,
    });
    expect(created.status).toBe(201);
    const updated = await w.a.patch(`/v1/products/${created.body.id}`, {
      name: "New cream 50 ml",
      active: false,
    });
    expect(updated.body).toMatchObject({
      name: "New cream 50 ml",
      active: false,
    });
    // Hidden products disappear for everyone but the admin.
    expect(
      (await w.n.get("/v1/products")).body.map((p: any) => p.reference),
    ).not.toContain("NEW-1");
    expect(
      (await w.a.get("/v1/products?includeInactive=true")).body.map(
        (p: any) => p.reference,
      ),
    ).toContain("NEW-1");
  });

  it("refuses two products with the same reference or barcode", async () => {
    const dup = await w.a.post("/v1/products", {
      reference: "P1",
      name: "Again",
      family: "Serums",
    });
    expect(dup.body.code).toBe("DUPLICATE");
    const barcode = await w.a.post("/v1/products", {
      reference: "OTHER",
      name: "Other",
      family: "Serums",
      barcode: "6000000000001",
    });
    expect(barcode.body.code).toBe("DUPLICATE");
  });

  it("imports many products, creating new ones and refreshing known ones", async () => {
    const photo = await w.a.upload("PRODUCT", fakeJpeg());
    const items = [
      {
        reference: "P1",
        name: "Serum Vitamin C 30 ml",
        family: "Serums",
        imageId: photo.body.id,
      },
      { reference: "I-2", name: "Imported", family: "Hair", imageId: null },
      {
        reference: "I-3",
        name: "Imported with picture",
        family: "Hair",
        imageId: photo.body.id,
      },
    ];
    const first = await w.a.post("/v1/products/import", { items });
    expect(first.body).toEqual({ created: 2, updated: 1 });
    const again = await w.a.post("/v1/products/import", { items });
    expect(again.body).toEqual({ created: 0, updated: 3 });
    const list = (await w.a.get("/v1/products")).body;
    expect(list.find((p: any) => p.reference === "P1")).toMatchObject({
      name: "Serum Vitamin C 30 ml",
      imageId: photo.body.id,
    });
  });

  it("finds a product by barcode and lists families", async () => {
    expect(
      (await w.n.get("/v1/products/barcode/6000000000001")).body.reference,
    ).toBe("P1");
    expect((await w.n.get("/v1/products/barcode/0000000000000")).status).toBe(
      404,
    );
    expect((await w.n.get("/v1/products/families")).body).toEqual([
      { family: "Hair", count: 1 },
      { family: "Serums", count: 2 },
    ]);
  });

  it("only accepts a product image uploaded for products, and only from the admin", async () => {
    const proof = await w.n.upload("PROOF", fakeJpeg());
    const bad = await w.a.post("/v1/products", {
      reference: "X",
      name: "X",
      family: "F",
      imageId: proof.body.id,
    });
    expect(bad.body.code).toBe("MEDIA_SCOPE");
    expect(
      (
        await w.n.post("/v1/products", {
          reference: "Y",
          name: "Y",
          family: "F",
        })
      ).status,
    ).toBe(403);
    const vendeur = client(api, (await createAccount({ role: "ADMIN" })).token);
    expect((await vendeur.get("/v1/products")).status).toBe(200);
  });
});
