const {PrismaClient}=require('/app/node_modules/@prisma/client'),{PrismaPg}=require('/app/node_modules/@prisma/adapter-pg'),assert=require('node:assert/strict');
if(!new URL(process.env.DATABASE_URL).pathname.endsWith('_deployment_test'))throw Error('Isolated database required');
const db=new PrismaClient({adapter:new PrismaPg({connectionString:process.env.DATABASE_URL})});
(async()=>{
 const stale=await db.job.findUniqueOrThrow({where:{id:process.env.PROBE_STALE_ID}});
 assert.equal(stale.status,'completed');assert.equal(stale.attempts,2);
 const result=await db.job.updateMany({where:{id:process.env.PROBE_FAILED_ID,status:'failed'},data:{status:'pending',attempts:0,availableAt:new Date(),lockedAt:null,leaseToken:null}});assert.equal(result.count,1);
 for(let n=0;n<20;n++){const j=await db.job.findUniqueOrThrow({where:{id:process.env.PROBE_FAILED_ID}});if(j.status==='completed')break;await new Promise(r=>setTimeout(r,500))}
 const recovered=await db.job.findUniqueOrThrow({where:{id:process.env.PROBE_FAILED_ID}});assert.equal(recovered.status,'completed');assert.equal(recovered.attempts,1);
 for(const id of [stale.id,recovered.id])assert.equal(await db.processedOperation.count({where:{id}}),1);
 console.log('PASS: stale lease recovered after worker restart, failed job diagnosed and resumed; one accepted operation per job.');
})().catch(e=>{console.error(e);process.exitCode=1}).finally(()=>db.$disconnect());
