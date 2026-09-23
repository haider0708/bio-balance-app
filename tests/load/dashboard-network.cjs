/* Bounded service benchmark against the isolated, reconciled synthetic database. */
const { Client } = require('pg');
const { randomUUID, randomBytes, createHash } = require('node:crypto');
const assert = require('node:assert/strict');
const ownerUrl=process.env.LOAD_OWNER_DATABASE_URL,appUrl=process.env.DATABASE_URL;
for(const u of [ownerUrl,appUrl])if(!u || !new URL(u).pathname.endsWith('_load_test'))throw Error('Isolated load database required');
const a=new URL(ownerUrl),b=new URL(appUrl);assert.equal(a.host+a.pathname,b.host+b.pathname);
const owner=new Client({connectionString:ownerUrl});
const { Database }=require('../../apps/api/dist/shared/infrastructure/database');
const { DashboardService }=require('../../apps/api/dist/modules/reporting/dashboard.service');
const db=new Database();
(async()=>{
 await owner.connect();const id=randomUUID();
 const row=await owner.query(`INSERT INTO "User"(id,email,name,"passwordHash","platformAdmin","createdAt") VALUES ($1,'load-admin@example.test','Synthetic dashboard benchmark','!synthetic-no-login',true,now()) ON CONFLICT(email) DO UPDATE SET name=EXCLUDED.name RETURNING id,email,name,"platformAdmin"`,[id]);
 const user=row.rows[0];assert.equal(user.platformAdmin,true);
 const sessionId=randomUUID(),token=randomBytes(32).toString('base64url');
 await owner.query('INSERT INTO "Session"(id,"userId","tokenHash","expiresAt") VALUES($1,$2,$3,now()+interval \'1 hour\')',[sessionId,user.id,createHash('sha256').update(token).digest('hex')]);
 try {
  const service=new DashboardService(db),today=new Date(Date.now()+3600000).toISOString().slice(0,10),times=[];
  let result;
  for(let i=0;i<55;i++){const start=performance.now();result=await service.get({...user,sessionId},{scope:'network',from:today.slice(0,8)+'01',to:today});if(i>=5)times.push(performance.now()-start);}
  times.sort((x,y)=>x-y);assert.equal(result.storeCount,500);
  console.log(JSON.stringify({kind:'network dashboard service; excludes HTTP/network; 5 warmup reads',samples:times.length,p50Ms:times[Math.ceil(times.length*.5)-1],p95Ms:times[Math.ceil(times.length*.95)-1],maxMs:times.at(-1),stores:result.storeCount,groups:result.groupCount,netMillimes:String(result.netMillimes)}));
 }finally{await owner.query('UPDATE "Session" SET "revokedAt"=now() WHERE id=$1',[sessionId]);}
})().catch(e=>{console.error(e);process.exitCode=1}).finally(async()=>{await db.$disconnect();await owner.end()});
