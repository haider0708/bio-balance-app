import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import {
  client,
  createAccount,
  fakeJpeg,
  resetDatabase,
  startApi,
  type Api,
} from "./helpers";
import {
  approvedPdv,
  buildWorld,
  levels,
  photo,
  stockPlace,
  teamMember,
  type World,
} from "./world";

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

describe("media", () => {
  it("accepts a real photo and refuses other content", async () => {
    const ok = await w.n.upload("PROOF", fakeJpeg());
    expect(ok.status).toBe(201);
    expect(ok.body).toMatchObject({ mime: "image/jpeg", purpose: "PROOF" });
    const text = await w.n.upload(
      "PROOF",
      Buffer.from("this is not an image at all"),
    );
    expect(text.status).toBe(415);
    expect((await w.n.upload("PRODUCT", fakeJpeg())).status).toBe(403);
    expect((await w.a.upload("PRODUCT", fakeJpeg())).status).toBe(201);
  });

  it("keeps proof photos private to their author, the admin and the region", async () => {
    const id = await photo(w, w.nord);
    const fetchAs = (token: string) =>
      fetch(`${api.url}/v1/media/${id}`, {
        headers: { Authorization: `Bearer ${token}` },
      });
    expect((await fetchAs(w.nord.token)).status).toBe(200);
    expect((await fetchAs(w.admin.token)).status).toBe(200);
    expect((await fetchAs(w.sud.token)).status).toBe(404);
    expect((await fetchAs(w.gros.token)).status).toBe(404);
  });
});

describe("initial stock", () => {
  it("is inactive until the admin approves it, and approval can correct quantities", async () => {
    const pdv = await approvedPdv(w);
    const declared = await w.n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: await photo(w, w.nord),
      lines: [
        { productId: w.products[0]!.id, quantity: 20 },
        { productId: w.products[2]!.id, quantity: 8 },
      ],
    });
    expect(declared.status).toBe(201);
    expect(declared.body).toMatchObject({ kind: "INITIAL", status: "PENDING" });
    expect(await levels(w, pdv.id)).toEqual({});
    expect((await w.n.get("/v1/pdvs")).body[0].initialStock).toBe("PENDING");

    const again = await w.n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: await photo(w, w.nord),
      lines: [{ productId: w.products[1]!.id, quantity: 1 }],
    });
    expect(again.body.code).toBe("ALREADY_COUNTED");

    const approved = await w.a.post(
      `/v1/stock/declarations/${declared.body.id}/approve`,
      {
        lines: [{ productId: w.products[0]!.id, quantity: 18 }],
        note: "Counted 18 on the photo",
      },
    );
    expect(approved.body.status).toBe("APPROVED");
    expect(await levels(w, pdv.id)).toEqual({
      "Serum Vitamin C": 18,
      "Shampoo Argan": 8,
    });
    expect((await w.n.get("/v1/pdvs")).body[0].initialStock).toBe("APPROVED");
    expect(
      (await w.a.post(`/v1/stock/declarations/${declared.body.id}/approve`, {}))
        .status,
    ).toBe(409);

    // The count happens once: a second declaration is refused.
    const second = await w.n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: await photo(w, w.nord),
      lines: [{ productId: w.products[0]!.id, quantity: 15 }],
    });
    expect(second.status).toBe(409);
    expect(second.body.code).toBe("ALREADY_COUNTED");
  });

  it("lets a store with nothing on its shelves declare no stock, without a photo", async () => {
    const pdv = await approvedPdv(w);
    const empty = await w.n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      lines: [],
    });
    expect(empty.status).toBe(201);
    expect(empty.body.lines).toEqual([]);
    expect(
      (await w.a.post(`/v1/stock/declarations/${empty.body.id}/approve`, {}))
        .body.status,
    ).toBe("APPROVED");
    expect((await w.n.get("/v1/pdvs")).body[0].initialStock).toBe("APPROVED");
    const withLines = await w.n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      lines: [{ productId: w.products[0]!.id, quantity: 1 }],
    });
    expect(withLines.status).toBe(409);
  });

  it("can be rejected and declared again", async () => {
    const pdv = await approvedPdv(w);
    const first = (
      await w.n.post("/v1/stock/declarations", {
        locationId: pdv.id,
        photoId: await photo(w, w.nord),
        lines: [{ productId: w.products[0]!.id, quantity: 5 }],
      })
    ).body;
    expect(
      (await w.a.post(`/v1/stock/declarations/${first.id}/reject`, {})).status,
    ).toBe(400);
    await w.a.post(`/v1/stock/declarations/${first.id}/reject`, {
      note: "Photo is blurry",
    });
    const retry = await w.n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: await photo(w, w.nord),
      lines: [{ productId: w.products[0]!.id, quantity: 5 }],
    });
    expect(retry.status).toBe(201);
  });

  it("needs the author's own photo, and stays inside the region", async () => {
    const pdv = await approvedPdv(w);
    const body = (photoId: string) => ({
      locationId: pdv.id,
      photoId,
      lines: [{ productId: w.products[0]!.id, quantity: 5 }],
    });
    expect(
      (await w.n.post("/v1/stock/declarations", body(await photo(w, w.sud))))
        .body.code,
    ).toBe("PHOTO_REQUIRED");
    expect(
      (await w.s.post("/v1/stock/declarations", body(await photo(w, w.sud))))
        .status,
    ).toBe(404);
    expect((await w.s.get(`/v1/stock/locations/${pdv.id}`)).status).toBe(404);
  });

  it("a grossiste declares the depot stock the same way", async () => {
    await stockPlace(w, w.depotId, w.gros, [50, 40, 30]);
    expect(await levels(w, w.depotId)).toEqual({
      "Serum Vitamin C": 50,
      "Serum Niacinamide": 40,
      "Shampoo Argan": 30,
    });
    expect((await w.g.get(`/v1/stock/locations/${w.depotId}`)).status).toBe(
      200,
    );
  });
});

describe("restock through a grossiste", () => {
  it("runs request → assign → ship → receipt with photo → admin approval", async () => {
    const pdv = await approvedPdv(w);
    await stockPlace(w, w.depotId, w.gros, [50, 40, 30]);
    await stockPlace(w, pdv.id, w.nord, [1, 0, 0]);
    const [p1, p2] = w.products;

    const order = (
      await w.n.post("/v1/restocks", {
        destId: pdv.id,
        lines: [
          { productId: p1!.id, quantity: 10 },
          { productId: p2!.id, quantity: 6 },
        ],
      })
    ).body;
    expect(order).toMatchObject({
      status: "REQUESTED",
      number: expect.stringMatching(/^RS-\d{4}-\d{6}$/),
    });

    const assigned = await w.a.post(`/v1/restocks/${order.id}/assign`, {
      depotId: w.depotId,
    });
    expect(assigned.body).toMatchObject({
      status: "ASSIGNED",
      source: "GROSSISTE",
    });
    // The grossiste now sees it; the other region does not.
    expect((await w.g.get("/v1/restocks")).body).toHaveLength(1);
    expect((await w.s.get("/v1/restocks")).body).toHaveLength(0);

    const tooMany = await w.g.post(`/v1/restocks/${order.id}/ship`, {
      lines: [{ productId: p1!.id, quantity: 11 }],
    });
    expect(tooMany.body.code).toBe("TOO_MANY");
    const shipped = await w.g.post(`/v1/restocks/${order.id}/ship`, {
      lines: [
        { productId: p1!.id, quantity: 10 },
        { productId: p2!.id, quantity: 5 },
      ],
    });
    expect(shipped.body.status).toBe("SHIPPED");
    // Nothing has moved yet.
    expect((await levels(w, w.depotId))["Serum Vitamin C"]).toBe(50);

    // The responsable picks a team member to count the goods.
    const member = await teamMember(w, pdv.id);
    const chosen = await w.n.put(`/v1/restocks/${order.id}/receiver`, {
      userId: member.id,
    });
    expect(chosen.body.receiver.id).toBe(member.id);

    const m = client(api, member.token);
    expect((await m.get("/v1/restocks")).body).toHaveLength(1);
    const noPhoto = await m.post(`/v1/restocks/${order.id}/receipt`, {
      photoId: await photo(w, w.nord),
      lines: [],
    });
    expect(noPhoto.status).toBe(400);
    const missing = await m.post(`/v1/restocks/${order.id}/receipt`, {
      photoId: await photo(w, member),
      lines: [{ productId: p1!.id, quantity: 10 }],
    });
    expect(missing.body.code).toBe("LINE_MISSING");
    const received = await m.post(`/v1/restocks/${order.id}/receipt`, {
      photoId: await photo(w, member),
      lines: [
        { productId: p1!.id, quantity: 10 },
        { productId: p2!.id, quantity: 4 },
      ],
    });
    expect(received.body.status).toBe("RECEIVED");
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(1);

    // The admin sees the photo, disagrees with one quantity, and approves the corrected amounts.
    const reject = await w.a.post(`/v1/restocks/${order.id}/reject-receipt`, {
      note: "Recount please",
    });
    expect(reject.body.status).toBe("SHIPPED");
    await m.post(`/v1/restocks/${order.id}/receipt`, {
      photoId: await photo(w, member),
      lines: [
        { productId: p1!.id, quantity: 10 },
        { productId: p2!.id, quantity: 4 },
      ],
    });
    const done = await w.a.post(`/v1/restocks/${order.id}/approve`, {
      lines: [{ productId: p2!.id, quantity: 5 }],
    });
    expect(done.body.status).toBe("COMPLETED");
    expect(
      done.body.lines.map((l: any) => [l.shipped, l.received, l.approved]),
    ).toEqual([
      [5, 4, 5],
      [10, 10, 10],
    ]);

    expect(await levels(w, pdv.id)).toMatchObject({
      "Serum Vitamin C": 11,
      "Serum Niacinamide": 5,
    });
    expect(await levels(w, w.depotId)).toMatchObject({
      "Serum Vitamin C": 40,
      "Serum Niacinamide": 35,
    });
    expect(
      (await w.a.post(`/v1/restocks/${order.id}/approve`, {})).status,
    ).toBe(409);
  });

  it("refuses to ship what the depot does not hold", async () => {
    const pdv = await approvedPdv(w);
    await stockPlace(w, w.depotId, w.gros, [3, 0, 0]);
    const order = (
      await w.n.post("/v1/restocks", {
        destId: pdv.id,
        lines: [{ productId: w.products[0]!.id, quantity: 10 }],
      })
    ).body;
    await w.a.post(`/v1/restocks/${order.id}/assign`, { depotId: w.depotId });
    const res = await w.g.post(`/v1/restocks/${order.id}/ship`, {
      lines: [{ productId: w.products[0]!.id, quantity: 10 }],
    });
    expect(res.body.code).toBe("INSUFFICIENT_STOCK");
  });

  it("assigns only a grossiste of the same region", async () => {
    const pdv = await approvedPdv(w, "s", "Para Sud");
    const order = (
      await w.s.post("/v1/restocks", {
        destId: pdv.id,
        lines: [{ productId: w.products[0]!.id, quantity: 4 }],
      })
    ).body;
    const refused = await w.a.post(`/v1/restocks/${order.id}/assign`, {
      depotId: w.depotId,
    }); // the world's grossiste works for Nord
    expect(refused.status).toBe(409);
    expect(refused.body.code).toBe("DEPOT_OTHER_REGION");
    expect((await w.s.get("/v1/depots")).body).toEqual([]);
  });

  it("only the assigned grossiste can ship", async () => {
    const pdv = await approvedPdv(w);
    const order = (
      await w.n.post("/v1/restocks", {
        destId: pdv.id,
        lines: [{ productId: w.products[0]!.id, quantity: 2 }],
      })
    ).body;
    await w.a.post(`/v1/restocks/${order.id}/assign`, { depotId: w.depotId });
    const other = await createAccount({
      role: "GROSSISTE",
      depot: { name: "Other depot" },
    });
    const res = await client(api, other.token).post(
      `/v1/restocks/${order.id}/ship`,
      { lines: [{ productId: w.products[0]!.id, quantity: 1 }] },
    );
    expect(res.status).toBe(404);
  });
});

describe("direct restock from BioBalance", () => {
  it("ships from unlimited stock and leaves every depot untouched", async () => {
    const pdv = await approvedPdv(w);
    await stockPlace(w, w.depotId, w.gros, [5, 5, 5]);
    const order = (
      await w.n.post("/v1/restocks", {
        destId: pdv.id,
        lines: [{ productId: w.products[0]!.id, quantity: 100 }],
      })
    ).body;
    const sent = await w.a.post(`/v1/restocks/${order.id}/send-direct`, {});
    expect(sent.body).toMatchObject({
      status: "SHIPPED",
      source: "BIOBALANCE",
    });
    await w.n.post(`/v1/restocks/${order.id}/receipt`, {
      photoId: await photo(w, w.nord),
      lines: [{ productId: w.products[0]!.id, quantity: 100 }],
    });
    await w.a.post(`/v1/restocks/${order.id}/approve`, {});
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(100);
    expect((await levels(w, w.depotId))["Serum Vitamin C"]).toBe(5);
  });

  it("the grossiste can ask BioBalance for stock too", async () => {
    const order = (
      await w.g.post("/v1/restocks", {
        lines: [{ productId: w.products[1]!.id, quantity: 60 }],
      })
    ).body;
    expect(order).toMatchObject({
      status: "REQUESTED",
      destination: { id: w.depotId, kind: "DEPOT" },
    });
    expect(
      (
        await w.a.post(`/v1/restocks/${order.id}/assign`, {
          depotId: w.depotId,
        })
      ).status,
    ).toBe(409);
    await w.a.post(`/v1/restocks/${order.id}/send-direct`, {});
    await w.g.post(`/v1/restocks/${order.id}/receipt`, {
      photoId: await photo(w, w.gros),
      lines: [{ productId: w.products[1]!.id, quantity: 60 }],
    });
    await w.a.post(`/v1/restocks/${order.id}/approve`, {});
    expect((await levels(w, w.depotId))["Serum Niacinamide"]).toBe(60);
  });

  it("can be cancelled by its requester only while waiting", async () => {
    const pdv = await approvedPdv(w);
    const order = (
      await w.n.post("/v1/restocks", {
        destId: pdv.id,
        lines: [{ productId: w.products[0]!.id, quantity: 2 }],
      })
    ).body;
    expect(
      (
        await w.n.post(`/v1/restocks/${order.id}/cancel`, {
          note: "Ordered by mistake",
        })
      ).body.status,
    ).toBe("CANCELLED");
    const second = (
      await w.n.post("/v1/restocks", {
        destId: pdv.id,
        lines: [{ productId: w.products[0]!.id, quantity: 2 }],
      })
    ).body;
    await w.a.post(`/v1/restocks/${second.id}/send-direct`, {});
    expect(
      (await w.n.post(`/v1/restocks/${second.id}/cancel`, { note: "Too late" }))
        .status,
    ).toBe(403);
  });
});
