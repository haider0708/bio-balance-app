import {
  client,
  createAccount,
  fakeJpeg,
  type Account,
  type Api,
} from "./helpers";

/** A small world used by most tests: an admin, a responsable in two regions, one grossiste and some products. */
export async function buildWorld(api: Api) {
  const admin = await createAccount({ role: "ADMIN", name: "Admin" });
  const nord = await createAccount({
    role: "RESPONSABLE",
    regionCode: "NORD",
    name: "Nora Nord",
  });
  const sud = await createAccount({
    role: "RESPONSABLE",
    regionCode: "SUD",
    name: "Sami Sud",
  });
  const gros = await createAccount({
    role: "GROSSISTE",
    name: "Hedi",
    depot: { name: "Depot Hedi" },
  });
  const a = client(api, admin.token);
  const products: { id: string; name: string; family: string }[] = [];
  for (const [reference, name, family] of [
    ["P1", "Serum Vitamin C", "Serums"],
    ["P2", "Serum Niacinamide", "Serums"],
    ["P3", "Shampoo Argan", "Hair"],
  ] as const)
    products.push(
      (
        await a.post("/v1/products", {
          reference,
          name,
          family,
          barcode: `600000000000${reference.slice(1)}`,
        })
      ).body,
    );
  const me = (await client(api, gros.token).get("/v1/depots")).body[0];
  return {
    api,
    admin,
    nord,
    sud,
    gros,
    products,
    depotId: me.id as string,
    a,
    n: client(api, nord.token),
    s: client(api, sud.token),
    g: client(api, gros.token),
  };
}

export type World = Awaited<ReturnType<typeof buildWorld>>;

/** Create an approved point of sale in a region and return it. */
export async function approvedPdv(
  w: World,
  as: "n" | "s" = "n",
  name = "Para Lac",
) {
  const c = as === "n" ? w.n : w.s;
  const created = await c.post("/v1/pdvs", {
    name,
    address: "12 rue du Lac",
    city: "Tunis",
  });
  const approved = await w.a.post(`/v1/pdvs/${created.body.id}/approve`, {});
  return approved.body as { id: string; name: string; regionId: string };
}

/** Upload a proof photo as `who` and return its id. */
export async function photo(w: World, who: Account) {
  const up = await client(w.api, who.token).upload("PROOF", fakeJpeg());
  if (up.status !== 201)
    throw new Error(`upload failed: ${JSON.stringify(up.body)}`);
  return up.body.id as string;
}

/** Declare `quantities` (per product, in the order of `w.products`) and have the admin approve them. */
export async function stockPlace(
  w: World,
  locationId: string,
  declarer: Account,
  quantities: number[],
) {
  const c = client(w.api, declarer.token);
  const declared = await c.post("/v1/stock/declarations", {
    locationId,
    photoId: await photo(w, declarer),
    lines: quantities.map((quantity, i) => ({
      productId: w.products[i]!.id,
      quantity,
    })),
  });
  if (declared.status !== 201)
    throw new Error(`declare failed: ${JSON.stringify(declared.body)}`);
  const approved = await w.a.post(
    `/v1/stock/declarations/${declared.body.id}/approve`,
    {},
  );
  if (approved.status !== 201)
    throw new Error(`approve failed: ${JSON.stringify(approved.body)}`);
  return approved.body;
}

/** An active team member of a point of sale who can sell. */
export async function teamMember(w: World, pdvId: string, name = "Karim") {
  return createAccount({ role: "VENDEUR", pdvId, name });
}

export async function levels(w: World, locationId: string) {
  const res = await w.a.get(`/v1/stock/locations/${locationId}`);
  return Object.fromEntries(
    (res.body.items as { name: string; quantity: number }[]).map((i) => [
      i.name,
      i.quantity,
    ]),
  );
}
