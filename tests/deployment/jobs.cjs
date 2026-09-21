const {PrismaClient}=require('/app/node_modules/@prisma/client'),{PrismaPg}=require('/app/node_modules/@prisma/adapter-pg');
const {randomUUID}=require('node:crypto');
if(!new URL(process.env.DATABASE_URL).pathname.endsWith('_deployment_test'))throw Error('Isolated database required');
const db=new PrismaClient({adapter:new PrismaPg({connectionString:process.env.DATABASE_URL})});
(async()=>{
 const store=await db.store.findFirstOrThrow();
 const stale=await db.job.create({data:{id:randomUUID(),kind:'inventory-check',key:'restart-'+randomUUID(),status:'running',attempts:1,lockedAt:new Date(Date.now()-16*60000),leaseToken:randomUUID(),payload:{storeId:store.id,organizationId:store.organizationId}}});
 const failed=await db.job.create({data:{id:randomUUID(),kind:'inventory-check',key:'recovery-'+randomUUID(),status:'failed',attempts:8,lastError:'SYNTHETIC_FAILURE',payload:{storeId:store.id,organizationId:store.organizationId}}});
 console.log(JSON.stringify({stale:stale.id,failed:failed.id}));
})().catch(e=>{console.error(e.name);process.exitCode=1}).finally(()=>db.$disconnect());
