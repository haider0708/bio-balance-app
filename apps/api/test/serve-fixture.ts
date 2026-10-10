/**
 * Starts the API on a test database with a realistic world, writes the connection details to a file,
 * then keeps running until a `<file>.stop` file appears. The mobile contract test connects to it
 * and parses every response. Run it with:
 *   FIXTURE_OUT=/path/fixture.json npx vitest run test/serve-fixture.test.ts
 */
import { existsSync, writeFileSync } from "node:fs";
import {
  client,
  createAccount,
  fakeJpeg,
  regionId,
  resetDatabase,
  startApi,
} from "./helpers";

export async function serveFixture(out: string) {
  await resetDatabase();
  const api = await startApi();
  const admin = await createAccount({
    role: "ADMIN",
    name: "Admin BioBalance",
  });
  const nord = await createAccount({
    role: "RESPONSABLE",
    regionCode: "NORD",
    name: "Nora Nord",
    email: "nora@example.test",
  });
  const sud = await createAccount({
    role: "RESPONSABLE",
    regionCode: "SUD",
    name: "Sami Sud",
  });
  const a = client(api, admin.token);
  const n = client(api, nord.token);
  const products: string[] = [];
  for (const [reference, name, family] of [
    ["P1", "Serum Vitamin C", "Sérums"],
    ["P2", "Serum Niacinamide", "Sérums"],
    ["P3", "Shampoing Argan", "Soins capillaires"],
  ] as const)
    products.push(
      (
        await a.post("/v1/products", {
          reference,
          name,
          family,
          barcode: `600000000000${reference.slice(1)}`,
        })
      ).body.id,
    );
  const photo = async (token: string) =>
    (await client(api, token).upload("PROOF", fakeJpeg())).body.id as string;
  const lines = (q: number[]) =>
    q.map((quantity, i) => ({ productId: products[i], quantity }));

  const group = (await n.post("/v1/groups", { name: "Groupe Tunis" })).body;
  await a.post(`/v1/groups/${group.id}/approve`, {});
  const pdv = (
    await n.post("/v1/pdvs", {
      name: "Para Lac",
      address: "12 rue du Lac",
      city: "Tunis",
      phone: "71 000 000",
      groupId: group.id,
    })
  ).body;
  await a.post(`/v1/pdvs/${pdv.id}/approve`, {});
  const waiting = (
    await n.post("/v1/pdvs", {
      name: "Para Marsa",
      address: "3 rue de la Marsa",
      city: "La Marsa",
    })
  ).body;

  const stock = (
    await n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: await photo(nord.token),
      lines: lines([20, 20, 20]),
    })
  ).body;
  await a.post(`/v1/stock/declarations/${stock.id}/approve`, {});
  const depotId = (
    await a.post("/v1/depots", {
      regionId: await regionId("NORD"),
      name: "Depot Hedi",
      address: "1 rue du Depot",
      city: "Tunis",
      phone: "71 111 111",
    })
  ).body.id;
  // The admin counts the grossiste's first stock with a photo; it applies at once.
  await a.post("/v1/stock/declarations", {
    locationId: depotId,
    photoId: await photo(admin.token),
    lines: lines([50, 40, 30]),
  });
  // A recount the admin allowed, counted again and still waiting for her decision.
  const recount = (
    await n.post("/v1/stock/recounts", {
      locationId: pdv.id,
      reason: "Checking the shelves",
    })
  ).body;
  await a.post(`/v1/stock/recounts/${recount.id}/approve`, {});
  const pendingStock = (
    await n.post("/v1/stock/declarations", {
      locationId: pdv.id,
      photoId: await photo(nord.token),
      lines: lines([18, 20]),
    })
  ).body;

  const member = (
    await n.post(`/v1/pdvs/${pdv.id}/members`, {
      name: "Karim Vendeur",
      email: "karim@example.test",
    })
  ).body;
  const memberAccount = await createAccount({
    role: "VENDEUR",
    pdvId: pdv.id,
    name: "Amira Vendeuse",
  });
  const vendeur = client(api, memberAccount.token);

  await a.post("/v1/reward-rules", {
    scope: "FAMILY",
    family: "Sérums",
    amountMillimes: 500,
    startsOn: new Date().toISOString().slice(0, 10),
  });
  await a.post("/v1/reward-rules", {
    scope: "PRODUCT",
    productId: products[0],
    amountMillimes: 800,
    startsOn: new Date().toISOString().slice(0, 10),
    note: "Promo",
  });
  const sale = (
    await vendeur.post("/v1/sales", {
      id: "11111111-1111-4111-8111-111111111111",
      lines: [
        { productId: products[0], quantity: 2 },
        { productId: products[1], quantity: 1 },
      ],
    })
  ).body;
  await vendeur.post(`/v1/sales/${sale.id}/correct`, {
    reason: "Recount",
    lines: [
      { productId: products[0], quantity: 1 },
      { productId: products[1], quantity: 1 },
    ],
  });
  const payout = (await vendeur.post("/v1/payouts", { amountMillimes: 500 }))
    .body;

  // One restock fully through the chain, one still waiting, one shipped.
  const done = (
    await n.post("/v1/restocks", {
      destId: pdv.id,
      lines: lines([5, 5]).map((l) => ({ ...l })),
    })
  ).body;
  await a.post(`/v1/restocks/${done.id}/assign`, { depotId });
  await n.post(`/v1/restocks/${done.id}/ship`, { lines: lines([5, 5]) });
  await n.put(`/v1/restocks/${done.id}/receiver`, { userId: memberAccount.id });
  await vendeur.post(`/v1/restocks/${done.id}/receipt`, {
    photoId: await photo(memberAccount.token),
    lines: lines([5, 4]),
  });
  await a.post(`/v1/restocks/${done.id}/approve`, { lines: lines([5, 5]) });
  const requested = (
    await n.post("/v1/restocks", { destId: pdv.id, lines: lines([3]) })
  ).body;
  const shipped = (
    await n.post("/v1/restocks", { destId: pdv.id, lines: lines([2, 2]) })
  ).body;
  await a.post(`/v1/restocks/${shipped.id}/send-direct`, {});
  const assigned = (
    await n.post("/v1/restocks", { destId: pdv.id, lines: lines([1]) })
  ).body;
  await a.post(`/v1/restocks/${assigned.id}/assign`, { depotId });

  const audience = { roles: ["VENDEUR"] };
  await a.post("/v1/messages", {
    title: "Nouveau sérum",
    body: "Découvrez-le cette semaine.",
    audience,
    pinned: true,
  });
  const course = (
    await a.post("/v1/courses", {
      title: "Vendre les sérums",
      summary: "Les bases",
    })
  ).body;
  await a.post(`/v1/courses/${course.id}/lessons`, {
    title: "Introduction",
    kind: "ARTICLE",
    body: "Bienvenue.",
    minutes: 4,
  });
  await a.post(`/v1/courses/${course.id}/publish`);

  writeFileSync(
    out,
    JSON.stringify({
      baseUrl: api.url,
      tokens: {
        admin: admin.token,
        responsable: nord.token,
        responsableSud: sud.token,
        vendeur: memberAccount.token,
      },
      ids: {
        pdv: pdv.id,
        waitingPdv: waiting.id,
        group: group.id,
        depot: depotId,
        product: products[0],
        product3: products[2],
        member: member.id,
        sale: sale.id,
        payout: payout.id,
        doneRestock: done.id,
        requestedRestock: requested.id,
        shippedRestock: shipped.id,
        assignedRestock: assigned.id,
        pendingStock: pendingStock.id,
        course: course.id,
      },
    }),
  );
  while (!existsSync(`${out}.stop`))
    await new Promise((r) => setTimeout(r, 500));
  await api.close();
}
