/* Renew only the synthetic fixture sessions; never regenerate business history. */
const {Client}=require('pg'),{readFile,writeFile}=require('node:fs/promises');
const {createHash,randomUUID}=require('node:crypto');
const url=process.env.LOAD_OWNER_DATABASE_URL;
if(!url || !new URL(url).pathname.endsWith('_load_test')) throw Error('Isolated load database required');
const db=new Client({connectionString:url});
(async()=>{
  await db.connect();
  const file=process.env.LOAD_FIXTURES??'.artifacts/load-fixtures.json';
  const fixtures=JSON.parse(await readFile(file,'utf8'));
  if(!Array.isArray(fixtures) || !fixtures.length) throw Error('Missing synthetic fixtures');
  await db.query('BEGIN');
  try {
    for(const f of fixtures) {
      const user=await db.query('SELECT email FROM "User" WHERE id=$1',[f.userId]);
      if(!/^load-\d+@example\.test$/.test(user.rows[0]?.email??'')) throw Error('Not a synthetic load account');
      const hash=createHash('sha256').update(f.token).digest('hex');
      await db.query('INSERT INTO "Session" (id,"userId","tokenHash","expiresAt") VALUES ($1,$2,$3,now()+interval \'12 hours\') ON CONFLICT ("tokenHash") DO UPDATE SET "expiresAt"=EXCLUDED."expiresAt","revokedAt"=NULL WHERE "Session"."userId"=EXCLUDED."userId"',[randomUUID(),f.userId,hash]);
      f.cursor=(await db.query('SELECT value::text FROM "StoreCursor" WHERE "storeId"=$1',[f.storeId])).rows[0]?.value??'0';
    }
    await db.query('COMMIT');
  } catch(error) {await db.query('ROLLBACK');throw error;}
  await writeFile(file,JSON.stringify(fixtures),{mode:0o600});
  console.log(`Refreshed ${fixtures.length} synthetic sessions and cached cursors; history preserved.`);
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>db.end());
