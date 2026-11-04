#!/usr/bin/env node
// Looks at (and sets up) the app's TestFlight side through the App Store Connect API key in ~/.biobalance/appstore/.
// Usage: node scripts/testflight.mjs status      builds, groups, the public link, the review details
//        node scripts/testflight.mjs release <build>   gives a processed build to the group "Testeurs" (the public link
//                                                      everyone is sent), lifts the link's 50-tester limit, and sends
//                                                      the build to Apple's beta review if it needs one
//        node scripts/testflight.mjs get <path>  one GET (for looking further)
// Reads ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH from the environment: `source ~/.biobalance/appstore/env.sh` first.
import { createPrivateKey, sign } from "node:crypto";
import { readFileSync } from "node:fs";

const APP = "6822445997";
const b64 = (v) => Buffer.from(v).toString("base64url");
const token = () => {
  const head = b64(JSON.stringify({ alg: "ES256", kid: process.env.ASC_KEY_ID, typ: "JWT" }));
  const now = Math.floor(Date.now() / 1000);
  const body = b64(JSON.stringify({ iss: process.env.ASC_ISSUER_ID, iat: now, exp: now + 600, aud: "appstoreconnect-v1" }));
  const key = createPrivateKey(readFileSync(process.env.ASC_KEY_PATH));
  const sig = sign("sha256", Buffer.from(`${head}.${body}`), { key, dsaEncoding: "ieee-p1363" });
  return `${head}.${body}.${b64(sig)}`;
};
export const call = async (method, path, body) => {
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: { authorization: `Bearer ${token()}`, "content-type": "application/json" },
    body: body && JSON.stringify(body),
  });
  const text = await res.text();
  const json = text ? JSON.parse(text) : {};
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${JSON.stringify(json.errors ?? json)}`);
  return json;
};

const [cmd, arg] = process.argv.slice(2);
if (cmd === "get") console.log(JSON.stringify(await call("GET", arg), null, 1));
else if (cmd === "status") {
  const builds = await call("GET", `/v1/builds?filter[app]=${APP}&sort=-uploadedDate&limit=5`);
  for (const b of builds.data) {
    const a = b.attributes;
    console.log(`build ${a.version}  ${a.processingState}  expired=${a.expired}  uploaded ${a.uploadedDate}  id ${b.id}`);
  }
  const groups = await call("GET", `/v1/apps/${APP}/betaGroups`);
  for (const g of groups.data) {
    const a = g.attributes;
    console.log(`group "${a.name}" internal=${a.isInternalGroup} publicLink=${a.publicLinkEnabled ? a.publicLink : "off"} id ${g.id}`);
  }
  const d = (await call("GET", `/v1/apps/${APP}/betaAppReviewDetail`)).data.attributes;
  console.log(`review details: contact=${d.contactEmail ?? "-"} demoAccountRequired=${d.demoAccountRequired} demoAccountName=${d.demoAccountName ? "set" : "-"}`);
} else if (cmd === "release") {
  const builds = await call("GET", `/v1/builds?filter[app]=${APP}&filter[version]=${arg}&limit=1`);
  const build = builds.data[0];
  if (!build) throw new Error(`Build ${arg} is not in App Store Connect yet.`);
  if (build.attributes.processingState !== "VALID") throw new Error(`Build ${arg} is ${build.attributes.processingState}: Apple is still processing it.`);
  const groups = await call("GET", `/v1/apps/${APP}/betaGroups`);
  const group = groups.data.find((g) => g.attributes.name === "Testeurs" && !g.attributes.isInternalGroup);
  if (!group) throw new Error('The external group "Testeurs" does not exist.');
  // Everyone gets the one public link: the default limit of 50 testers is too low for a network of stores.
  await call("PATCH", `/v1/betaGroups/${group.id}`, {
    data: { type: "betaGroups", id: group.id, attributes: { publicLinkLimitEnabled: false } },
  });
  await call("POST", `/v1/betaGroups/${group.id}/relationships/builds`, { data: [{ type: "builds", id: build.id }] });
  try {
    await call("POST", "/v1/betaAppReviewSubmissions", {
      data: { type: "betaAppReviewSubmissions", relationships: { build: { data: { type: "builds", id: build.id } } } },
    });
    console.log(`Build ${arg} sent to Apple's beta review.`);
  } catch (error) {
    console.log(`Beta review: ${error.message}`);
  }
  const detail = (await call("GET", `/v1/builds/${build.id}/buildBetaDetail`)).data.attributes;
  console.log(`Build ${arg} in "Testeurs": external state ${detail.externalBuildState}; link ${group.attributes.publicLink}`);
} else console.log("Usage: testflight.mjs status | get <path> | release <build>");
