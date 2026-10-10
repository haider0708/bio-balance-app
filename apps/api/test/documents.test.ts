import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { client, resetDatabase, startApi, type Api } from "./helpers";
import { approvedPdv, buildWorld, type World } from "./world";

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

const pdf = () =>
  Buffer.from("%PDF-1.4\n1 0 obj << >> endobj\ntrailer << >>\n%%EOF\n");

describe("documents as proof", () => {
  it("takes a PDF next to photos, says what each file is, and keeps it to the right people", async () => {
    const pdv = await approvedPdv(w);
    const n = client(api, w.nord.token);
    const up = await n.upload("PROOF", pdf());
    expect(up.status).toBe(201);
    expect(up.body.mime).toBe("application/pdf");

    // A stock count can carry the delivery note as a PDF.
    const declared = await n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoIds: [up.body.id],
      lines: [{ productId: w.products[0]!.id, quantity: 4 }],
    });
    expect(declared.status).toBe(201);

    const info = await n.get(`/v1/media/${up.body.id}/info`);
    expect(info.body).toMatchObject({
      id: up.body.id,
      mime: "application/pdf",
    });
    expect((await w.a.get(`/v1/media/${up.body.id}/info`)).status).toBe(200);
    // Another region's responsable sees nothing of it.
    expect((await w.s.get(`/v1/media/${up.body.id}/info`)).status).toBe(404);
  });

  it("still refuses what is neither a photo nor a PDF", async () => {
    const res = await client(api, w.nord.token).upload(
      "PROOF",
      Buffer.from("PK\u0003\u0004 not a document"),
    );
    expect(res.body.code).toBe("UNSUPPORTED_FILE");
  });
});
