#!/usr/bin/env bash
# A fresh local world for the on-device test: empty development database (regions kept),
# an administrator, the real catalogue, then the seeded accounts and activity.
# Writes the world (accounts) to $1 (default: /tmp/biobalance-world.json).
set -euo pipefail
cd "$(dirname "$0")/../.."
out=${1:-/tmp/biobalance-world.json}
setup=$(mktemp -d)/admin-setup.json
db=(docker exec biobalance-dev-postgres-1 psql -U biobalance -d biobalance)
tables=$("${db[@]}" -Atc "select string_agg(format('%I',tablename),',') from pg_tables where schemaname='public' and tablename not in ('_prisma_migrations','Region')")
"${db[@]}" -qc "TRUNCATE $tables RESTART IDENTITY CASCADE"
(cd apps/api && ADMIN_EMAIL=owner@example.test ADMIN_PASSWORD=owner-password ADMIN_SETUP_FILE=$setup node --env-file=.env dist/bootstrap-admin.js >/dev/null)
python3 - "$setup" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['password']='owner-password'; json.dump(d,open(p,'w'))
PY
otp=$(node -e "
const {createHmac}=require('crypto');const u=new URL(require('$setup').totpUri);const s=u.searchParams.get('secret');
const a='ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';let b='';for(const c of s.replace(/=+$/,''))b+=a.indexOf(c).toString(2).padStart(5,'0');
const k=Buffer.from(b.match(/.{8}/g).map(x=>parseInt(x,2)));const t=Buffer.alloc(8);t.writeBigUInt64BE(BigInt(Math.floor(Date.now()/30000)));
const h=createHmac('sha1',k).update(t).digest();const o=h[h.length-1]&15;console.log(String((h.readUInt32BE(o)&0x7fffffff)%1e6).padStart(6,'0'))")
API_URL=http://localhost:3000 ADMIN_EMAIL=owner@example.test ADMIN_PASSWORD=owner-password ADMIN_OTP=$otp node scripts/import-catalog.mjs | tail -1
sleep 31 # an authenticator code is accepted once: wait for the next 30-second step
node scripts/dev/seed-dev-world.mjs "$setup" "$out"
