/* Real Nest/HTTP/PostgreSQL + Flutter/SQLite recovery test. Synthetic test data only. */
const { randomUUID, createHash } = require('node:crypto');
const { spawn } = require('node:child_process');
const { resolve } = require('node:path');
const assert = require('node:assert/strict');
const { PrismaClient } = require('@prisma/client');
const { PrismaPg } = require('@prisma/adapter-pg');
const { NestFactory } = require('@nestjs/core');
require('reflect-metadata');
const appUrl = process.env.TEST_APP_DATABASE_URL ?? 'postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test';
const ownerUrl = process.env.TEST_OWNER_DATABASE_URL ?? 'postgresql://biobalance:local-development-only@localhost:54329/biobalance_test';
if (![appUrl, ownerUrl].every(value => new URL(value).pathname.endsWith('_test'))) throw Error('An isolated *_test database is required');
process.env.DATABASE_URL = appUrl;
const { AppModule } = require('../dist/app.module');
const owner = new PrismaClient({adapter: new PrismaPg({connectionString:ownerUrl})});
(async () => {
  const app = await NestFactory.create(AppModule,{logger:false});
  let session;
  try {
    const userId=randomUUID(), org=randomUUID(), storeId=randomUUID(), emptyStore=randomUUID(), productId=randomUUID(), token=randomUUID();
    await owner.user.create({data:{id:userId,email:`sync-${userId}@example.test`,name:'Offline test',passwordHash:'test-account-not-login-enabled'}});
    await owner.organization.create({data:{id:org,name:'Isolated mobile sync test'}});
    await owner.store.create({data:{id:storeId,organizationId:org,name:'Test store',address:'Test address',city:'Tunis'}});
    await owner.membership.create({data:{userId,storeId,organizationId:org,permissions:['manage','sell','receive']}});
    await owner.store.create({data:{id:emptyStore,organizationId:org,name:'Missing batch test',address:'Test address',city:'Tunis'}});
    await owner.membership.create({data:{userId,storeId:emptyStore,organizationId:org,permissions:['sell','receive']}});
    await owner.product.create({data:{id:productId,reference:productId,name:'Synthetic sync product'}});
    await owner.storeProduct.create({data:{storeId,organizationId:org,productId,priceMillimes:1000n,pointsPerUnit:10,pointsConfigured:true}});
    await owner.storeProduct.create({data:{storeId:emptyStore,organizationId:org,productId,priceMillimes:1000n,pointsPerUnit:10,pointsConfigured:true}});
    session=await owner.session.create({data:{userId,tokenHash:createHash('sha256').update(token).digest('hex'),expiresAt:new Date(Date.now()+600000)}});
    app.getHttpAdapter().getInstance().set('json replacer',(_k,v)=>typeof v==='bigint'?v.toString():v);
    await app.listen(0,'127.0.0.1');
    const code=await new Promise((resolveCode,reject)=>{
      const child=spawn(process.env.FLUTTER_BIN??'flutter',['test','test/sync_api_test.dart','--reporter','expanded'],{
        cwd:resolve(__dirname,'../../mobile'),stdio:'inherit',env:{...process.env,
          BIOBALANCE_TEST_TOKEN:token,BIOBALANCE_TEST_USER:userId,BIOBALANCE_TEST_STORE:storeId,
          BIOBALANCE_TEST_ORG:org,BIOBALANCE_TEST_PRODUCT:productId,BIOBALANCE_TEST_EMPTY_STORE:emptyStore,
          BIOBALANCE_TEST_URL:`http://127.0.0.1:${app.getHttpServer().address().port}`,
        },
      });
      child.on('error',reject);child.on('exit',resolveCode);
    });
    assert.equal(code,0,'Flutter recovery journey failed');
    const lot=await owner.inventoryLot.findFirstOrThrow({where:{storeId}});
    assert.deepEqual({sellable:lot.sellable,damaged:lot.damaged,version:lot.version},{sellable:7,damaged:1,version:7});
    assert.equal(await owner.stockMovement.count({where:{storeId}}),6);
    assert.equal(await owner.saleRevision.count({where:{storeId}}),3);
    assert.equal(await owner.processedOperation.count({where:{storeId}}),5);
    const points=await owner.pointsAccount.findUniqueOrThrow({where:{storeId_userId:{storeId,userId}}});
    assert.equal(points.balance,20n);
    const declared = await owner.inventoryLot.findFirstOrThrow({where:{storeId:emptyStore}});
    assert.deepEqual({sellable:declared.sellable,damaged:declared.damaged,version:declared.version},{sellable:-2,damaged:0,version:2});
    const movement = await owner.stockMovement.findMany({where:{storeId:emptyStore}});
    assert.equal(movement.length,1);assert.equal(movement[0].quantity,-2);assert.equal(movement[0].reason,'sale.create');
    console.log('PASS: missing batch metadata + actual outgoing sale; no artificial receipt.');
    console.log('PASS: real HTTP + SQLite + PostgreSQL recovery; 5 operations, 6 movements, 3 revisions, stock 7/1 v7, 20 points.');
  } finally {
    if(session) await owner.session.update({where:{id:session.id},data:{revokedAt:new Date()}});
    await app.close();await owner.$disconnect();
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
