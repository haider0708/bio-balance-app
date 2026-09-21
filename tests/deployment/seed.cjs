// Executed only inside the one-off migration container, against its isolated DB.
const { PrismaClient } = require('/app/node_modules/@prisma/client');
const { PrismaPg } = require('/app/node_modules/@prisma/adapter-pg');
const { randomUUID, createHash } = require('node:crypto');
const url=process.env.DATABASE_URL;
if (!url || !new URL(url).pathname.endsWith('_deployment_test')) throw Error('Isolated deployment database required');
const db=new PrismaClient({adapter:new PrismaPg({connectionString:url})});
(async()=>{
 const admin=await db.user.findFirstOrThrow({where:{platformAdmin:true}});
 const organization=await db.organization.create({data:{name:'Isolated deployment fixture'}});
 const result={organizationId:organization.id,adminId:admin.id};
 for (const role of ['manager','outsider']) {
  const id=randomUUID(),token=randomUUID()+randomUUID();
  await db.user.create({data:{id,email:`${id}@example.test`,name:`Deployment ${role}`,passwordHash:'!synthetic-session-only'}});
  await db.session.create({data:{userId:id,tokenHash:createHash('sha256').update(token).digest('hex'),expiresAt:new Date(Date.now()+86400000)}});
  result[role+'Id']=id;result[role+'Token']=token;
 }
 await db.organizationMembership.create({data:{organizationId:organization.id,userId:result.managerId}});
 console.log(JSON.stringify(result));
})().catch(e=>{console.error(e.name);process.exitCode=1}).finally(()=>db.$disconnect());
