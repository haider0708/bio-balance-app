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

describe("several photos", () => {
  it("takes one to five photos for a count and for a delivery, and refuses six", async () => {
    const pdv = await approvedPdv(w);
    const photos = async (n: number) =>
      Promise.all(Array.from({ length: n }, () => photo(w, w.nord)));
    const body = (photoIds: string[]) => ({
      locationId: pdv.id,
      photoIds,
      lines: [{ productId: w.products[0]!.id, quantity: 5 }],
    });
    const six = await w.n.post("/v1/stock/declarations", body(await photos(6)));
    expect(six.status).toBe(400);
    const dup = await photos(1);
    const twice = await w.n.post(
      "/v1/stock/declarations",
      body([dup[0]!, dup[0]!]),
    );
    expect(twice.body.code).toBe("TOO_MANY_PHOTOS");
    const other = await photo(w, w.sud);
    const stolen = await w.n.post("/v1/stock/declarations", body([other]));
    expect(stolen.body.code).toBe("PHOTO_REQUIRED");
    const mine = await photos(3);
    const ok = await w.n.post("/v1/stock/declarations", body(mine));
    expect(ok.status).toBe(201);
    expect(ok.body.photoIds).toEqual(mine);
    expect(ok.body.photoId).toBe(mine[0]);
    // The admin can open them all.
    for (const id of mine) {
      const res = await fetch(`${api.url}/v1/media/${id}`, {
        headers: { Authorization: `Bearer ${w.admin.token}` },
      });
      expect(res.status).toBe(200);
    }
  });
});

describe("the grossiste's count goes through the responsable", () => {
  const count = async (photoIds: string[]) => ({
    locationId: w.depotId,
    photoIds,
    lines: [{ productId: w.products[0]!.id, quantity: 30 }],
  });

  it("is checked by the responsable of the region, then approved by the admin", async () => {
    const declared = await w.g.post(
      "/v1/stock/declarations",
      await count([await photo(w, w.gros)]),
    );
    expect(declared.status).toBe(201);
    expect(declared.body.status).toBe("REVIEW");
    // The admin cannot skip the check; the other region cannot see it.
    expect(
      (await w.a.post(`/v1/stock/declarations/${declared.body.id}/approve`, {}))
        .status,
    ).toBe(409);
    expect([403, 404]).toContain(
      (await w.s.get(`/v1/stock/declarations/${declared.body.id}`)).status,
    );
    // The responsable sees the numbers and the photos, and the depot's levels.
    const seen = await w.n.get(`/v1/stock/declarations/${declared.body.id}`);
    expect(seen.body.photoIds).toHaveLength(1);
    expect(
      (await w.n.get("/v1/stock/declarations?status=REVIEW")).body,
    ).toHaveLength(1);
    expect((await w.n.get(`/v1/stock/locations/${w.depotId}`)).status).toBe(
      200,
    );
    expect((await w.s.get(`/v1/stock/locations/${w.depotId}`)).status).toBe(
      404,
    );
    // Sent back with a reason, the grossiste can count again at once.
    const refused = await w.n.post(
      `/v1/stock/declarations/${declared.body.id}/review`,
      { action: "reject" },
    );
    expect(refused.body.code).toBe("NOTE_REQUIRED");
    await w.n.post(`/v1/stock/declarations/${declared.body.id}/review`, {
      action: "reject",
      note: "Photo too dark",
    });
    const again = await w.g.post(
      "/v1/stock/declarations",
      await count([await photo(w, w.gros)]),
    );
    expect(again.body.status).toBe("REVIEW");
    const passed = await w.n.post(
      `/v1/stock/declarations/${again.body.id}/review`,
      { action: "approve" },
    );
    expect(passed.body.status).toBe("PENDING");
    const done = await w.a.post(
      `/v1/stock/declarations/${again.body.id}/approve`,
      {},
    );
    expect(done.body.status).toBe("APPROVED");
    expect(await levels(w, w.depotId)).toEqual({ "Serum Vitamin C": 30 });
    // Only the responsable of that region reviews.
    expect(
      (
        await w.s.post(`/v1/stock/declarations/${again.body.id}/review`, {
          action: "approve",
        })
      ).status,
    ).toBe(404);
  });

  it("goes straight to the admin when the responsable declares it", async () => {
    const declared = await w.n.post(
      "/v1/stock/declarations",
      await count([await photo(w, w.nord)]),
    );
    expect(declared.status).toBe(201);
    expect(declared.body.status).toBe("PENDING");
  });
});

describe("counting again needs the admin's permission", () => {
  it("opens one recount per approval, for a store and for a grossiste", async () => {
    const pdv = await approvedPdv(w);
    await stockPlace(w, pdv.id, w.nord, [10, 10, 10]);
    const redo = (photoIds: string[]) => ({
      locationId: pdv.id,
      photoIds,
      lines: [{ productId: w.products[0]!.id, quantity: 4 }],
    });
    // No permission: refused.
    expect(
      (await w.n.post("/v1/stock/declarations", redo([await photo(w, w.nord)])))
        .body.code,
    ).toBe("ALREADY_COUNTED");
    // Ask; the admin refuses; nothing changes.
    const asked = await w.n.post("/v1/stock/recounts", {
      locationId: pdv.id,
      reason: "Bought from another shop",
    });
    expect(asked.status).toBe(201);
    expect(
      (
        await w.n.post("/v1/stock/recounts", {
          locationId: pdv.id,
          reason: "again",
        })
      ).body.code,
    ).toBe("RECOUNT_PENDING");
    expect((await w.a.get("/v1/approvals")).body.counts.RECOUNT).toBe(1);
    expect(
      (await w.n.post(`/v1/stock/recounts/${asked.body.id}/approve`, {}))
        .status,
    ).toBe(403);
    await w.a.post(`/v1/stock/recounts/${asked.body.id}/reject`, {
      note: "Not needed",
    });
    expect(
      (await w.n.post("/v1/stock/declarations", redo([await photo(w, w.nord)])))
        .body.code,
    ).toBe("ALREADY_COUNTED");
    expect(await levels(w, pdv.id)).toEqual({
      "Serum Vitamin C": 10,
      "Serum Niacinamide": 10,
      "Shampoo Argan": 10,
    });
    // Ask again; approved; one recount, which still waits for the admin.
    const second = await w.n.post("/v1/stock/recounts", {
      locationId: pdv.id,
      reason: "Bought from another shop",
    });
    await w.a.post(`/v1/stock/recounts/${second.body.id}/approve`, {});
    const recount = await w.n.post(
      "/v1/stock/declarations",
      redo([await photo(w, w.nord)]),
    );
    expect(recount.status).toBe(201);
    expect(recount.body.kind).toBe("COUNT");
    expect(recount.body.status).toBe("PENDING");
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(10);
    await w.a.post(`/v1/stock/declarations/${recount.body.id}/approve`, {});
    expect((await levels(w, pdv.id))["Serum Vitamin C"]).toBe(4);
    // The permission was used up.
    expect(
      (await w.n.post("/v1/stock/declarations", redo([await photo(w, w.nord)])))
        .body.code,
    ).toBe("ALREADY_COUNTED");

    // A grossiste recounts the same way, and the recount goes through the responsable.
    await stockPlace(w, w.depotId, w.gros, [20, 20, 20]);
    const g = await w.g.post("/v1/stock/recounts", {
      locationId: w.depotId,
      reason: "Bought stock elsewhere",
    });
    expect(g.status).toBe(201);
    await w.a.post(`/v1/stock/recounts/${g.body.id}/approve`, {});
    const gcount = await w.g.post("/v1/stock/declarations", {
      locationId: w.depotId,
      photoIds: [await photo(w, w.gros)],
      lines: [{ productId: w.products[0]!.id, quantity: 45 }],
    });
    expect(gcount.body.status).toBe("REVIEW");
    expect(gcount.body.kind).toBe("COUNT");
  });

  it("cannot be asked for a place that was never counted, or for another region's place", async () => {
    const pdv = await approvedPdv(w);
    expect(
      (
        await w.n.post("/v1/stock/recounts", {
          locationId: pdv.id,
          reason: "why not",
        })
      ).body.code,
    ).toBe("NOT_COUNTED_YET");
    await stockPlace(w, pdv.id, w.nord, [1, 1, 1]);
    expect([403, 404]).toContain(
      (
        await w.s.post("/v1/stock/recounts", {
          locationId: pdv.id,
          reason: "spy",
        })
      ).status,
    );
  });
});

describe("the admin corrects stock", () => {
  it("sets quantities with a reason, keeps the history and tells the people in charge", async () => {
    await stockPlace(w, w.depotId, w.gros, [20, 20, 20]);
    const res = await w.a.post("/v1/stock/adjust", {
      locationId: w.depotId,
      reason: "Damaged in transport",
      lines: [
        { productId: w.products[0]!.id, quantity: 12 },
        { productId: w.products[1]!.id, quantity: 20 },
      ],
    });
    expect(res.status).toBe(201);
    expect(res.body.changed).toBe(1);
    expect((await levels(w, w.depotId))["Serum Vitamin C"]).toBe(12);
    const movements = await w.a.get(
      `/v1/stock/locations/${w.depotId}/products/${w.products[0]!.id}/movements`,
    );
    expect(movements.body[0]).toMatchObject({
      delta: -8,
      reason: "ADJUSTMENT",
    });
    expect(
      (
        await w.g.post("/v1/stock/adjust", {
          locationId: w.depotId,
          reason: "mine",
          lines: [{ productId: w.products[0]!.id, quantity: 99 }],
        })
      ).status,
    ).toBe(403);
    expect(
      (
        await w.a.post("/v1/stock/adjust", {
          locationId: w.depotId,
          reason: "no",
          lines: [{ productId: w.products[0]!.id, quantity: -1 }],
        })
      ).status,
    ).toBe(400);
    const told = await client(api, w.gros.token).get("/v1/notifications");
    expect(told.body.items.some((n: any) => n.key === "stock.adjusted")).toBe(
      true,
    );
  });
});
