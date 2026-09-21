/* Validates every public route against real Nest HTTP responses on an isolated database. */
const assert=require('node:assert/strict');
const {randomUUID,createHash}=require('node:crypto');
const {mkdtemp,readFile,writeFile,rm}=require('node:fs/promises');
const {tmpdir}=require('node:os');const path=require('node:path');
const {NestFactory}=require('@nestjs/core');const {json,raw}=require('express');
const {PrismaClient}=require('@prisma/client');const {PrismaPg}=require('@prisma/adapter-pg');
const argon2=require('argon2');const Ajv=require('ajv/dist/2020').default;const addFormats=require('ajv-formats');
require('reflect-metadata');
const appUrl=process.env.TEST_APP_DATABASE_URL??'postgresql://biobalance_app:local-app-only@localhost:54329/biobalance_test';
const ownerUrl=process.env.TEST_OWNER_DATABASE_URL??'postgresql://biobalance:local-development-only@localhost:54329/biobalance_test';
if(![appUrl,ownerUrl].every(v=>new URL(v).pathname.endsWith('_test')))throw Error('ISOLATED_TEST_DATABASE_REQUIRED');
process.env.DATABASE_URL=appUrl;
const owner=new PrismaClient({adapter:new PrismaPg({connectionString:ownerUrl})});
(async()=>{
 const root=await mkdtemp(path.join(tmpdir(),'biobalance-contract-'));process.env.MEDIA_ROOT=root;
 const {AppModule}=require('../dist/app.module');
 const {MediaProcessor}=require('../dist/modules/training/infrastructure/media-processor');
 const {Database}=require('../dist/shared/infrastructure/database');
 const {contract}=require('../dist/openapi');
 const document=await contract(),ajv=new Ajv({strict:false,allErrors:true});addFormats(ajv);ajv.addFormat('binary',true);
 ajv.addSchema({$id:'biobalance',components:document.components});
 const validate=schema=>ajv.compile({...schema,components:document.components});
 const routes=Object.entries(document.paths).flatMap(([route,item])=>Object.entries(item).filter(([m])=>['get','post','patch','put','delete'].includes(m)).map(([method,spec])=>({method,route,spec,regex:new RegExp('^'+route.replace(/\{[^}]+\}/g,'[^/]+')+'$')})));
 const validators=new Map();const seen=new Set();const fixtures=[];
 for(const route of routes){
  assert(route.spec.responses['200']||route.spec.responses['201'],'success contract required');
  for(const response of Object.values(route.spec.responses))for(const [mime,content] of Object.entries(response.content??{}))if(mime==='application/json')validate(content.schema);
 }
 const app=await NestFactory.create(AppModule,{logger:false,bodyParser:false});app.use('/v1/media/uploads',raw({type:'application/octet-stream',limit:'4mb'}));app.use(json({limit:'1mb'}));
 app.getHttpAdapter().getInstance().set('json replacer',(_k,v)=>typeof v==='bigint'?v.toString():v);
 let token,adminToken,base;
 const call=async(method,url,{body,as=token,status=method==='POST'?201:200,headers={}}={})=>{
  const route=routes.find(r=>r.method===method.toLowerCase()&&r.regex.test(url.split('?')[0]));assert(route,`unknown route ${method} ${url}`);
  if(body && !Buffer.isBuffer(body)) {
   const schema=route.spec.requestBody?.content?.['application/json']?.schema;assert(schema,'request contract');
   const valid=validate(schema);assert(valid(body),`${route.spec.operationId} request: ${ajv.errorsText(valid.errors)}`);
  }
  const response=await fetch(base+url,{method,headers:{...(as?{Authorization:`Bearer ${as}`} : {}),...(body?{'Content-Type':Buffer.isBuffer(body)?'application/octet-stream':'application/json'}:{}),...headers},...(body?{body:Buffer.isBuffer(body)?body:JSON.stringify(body)}:{})});
  const mime=response.headers.get('content-type')??'';const value=mime.includes('application/json')?await response.json():Buffer.from(await response.arrayBuffer());
  assert.equal(response.status,status,`${route.spec.operationId}: ${JSON.stringify(value)}`);
  const content=route.spec.responses[`${status}`]?.content;assert(content,`missing status ${status}`);
  if(mime.includes('application/json')) {
   const key=route.spec.operationId+status;let valid=validators.get(key);if(!valid){valid=validate(content['application/json'].schema);validators.set(key,valid);}
   assert(valid(value),`${key}: ${ajv.errorsText(valid.errors)} ${JSON.stringify(valid.errors?.slice(0,4))}`);
  }
  if(status<300){seen.add(route.spec.operationId);if(mime.includes('application/json'))fixtures.push({operationId:route.spec.operationId,value});}
  return value;
 };
 try {
  const managerId=randomUUID(),adminId=randomUUID(),staffId=randomUUID(),org=randomUUID();
  const password='Synthetic-contract-password-4831';const passwordHash=await argon2.hash(password);
  for(const [id,isAdmin] of [[managerId,false],[adminId,true],[staffId,false]])await owner.user.create({data:{id,email:`${id}@example.test`,name:'Contract fixture',passwordHash,platformAdmin:isAdmin}});
  await owner.organization.create({data:{id:org,name:'Contract fixtures'}});
  await owner.organizationMembership.create({data:{organizationId:org,userId:managerId}});
  adminToken=randomUUID();await owner.session.create({data:{userId:adminId,tokenHash:createHash('sha256').update(adminToken).digest('hex'),expiresAt:new Date(Date.now()+600000)}});
  await app.listen(0,'127.0.0.1');base=`http://127.0.0.1:${app.getHttpServer().address().port}`;
  await call('GET','/health',{as:null});
  token=(await call('POST','/v1/identity/login',{as:null,body:{email:`${managerId}@example.test`,password}})).token;
  await call('GET','/v1/identity/me');await call('GET','/v1/identity/me',{as:null,status:401});
  await call('GET','/v1/organizations');
  const store=(await call('POST','/v1/stores',{body:{organizationId:org,name:'Contract store',address:'Rue de test',city:'Tunis'}})).id;
  const scope=`organizationId=${org}`;const storeUrl=`/v1/stores/${store}`;
  await owner.membership.create({data:{organizationId:org,storeId:store,userId:staffId,permissions:['sell','receive']}});
  await call('GET','/v1/stores');
  await call('PATCH',`${storeUrl}?${scope}`,{body:{name:'Updated store',address:'Rue de test',city:'Tunis',phone:null,imageId:null,expectedVersion:1}});
  const invitation=await call('POST','/v1/identity/invitations',{body:{email:`invite-${randomUUID()}@example.test`,organizationId:org,storeId:store,permissions:['sell']}});
  const mail=await owner.job.findUniqueOrThrow({where:{key:`invite:${invitation.id}`}});
  const activation=new URL(mail.payload.text.match(/biobalance:\/\/activate\?token=[\w-]+/)[0]).searchParams.get('token');
  await call('POST','/v1/identity/activate',{as:null,body:{token:activation,name:'Invited seller',password}});
  await call('POST','/v1/identity/forgot-password',{as:null,body:{email:invitation.email}});
  const recovery=await owner.job.findFirstOrThrow({where:{kind:'email',payload:{path:['to'],equals:invitation.email}},orderBy:{createdAt:'desc'}});
  const recoveryToken=new URL(recovery.payload.text.match(/biobalance:\/\/recover\?token=[\w-]+/)[0]).searchParams.get('token');
  await call('POST','/v1/identity/reset-password',{as:null,body:{token:recoveryToken,password:password+'-new'}});
  const product=await call('POST','/v1/catalog/products',{as:adminToken,body:{reference:randomUUID(),name:'Contract product',description:'Fixture',active:true}});
  await call('POST','/v1/catalog/import',{as:adminToken,body:{rows:[{reference:randomUUID(),name:'Import fixture'}],commit:false}});
  await call('POST','/v1/catalog/import',{as:adminToken,body:{rows:[{reference:randomUUID(),name:'Import fixture'}],commit:true}});
  await call('PATCH',`${storeUrl}/products/${product.id}?${scope}`,{body:{priceMillimes:'12345',threshold:5,pointsPerUnit:10}});
  await call('PATCH',`${storeUrl}/team/${staffId}?${scope}`,{body:{active:true,permissions:['sell','receive']}});
  await call('PATCH',`${storeUrl}/onboarding?${scope}`,{body:{workingAlone:false,noOpeningStock:false,expectedVersion:2}});
  const envelope=(command,expectedVersion)=>({operationId:randomUUID(),organizationId:org,storeId:store,payloadVersion:2,...(expectedVersion?{expectedVersion}:{}),command});
  const push=async(operation,as=token)=>(await call('POST','/v1/sync/push',{as,body:{operations:[operation]}})).results[0];
  const receipt=envelope({type:'stock.receive',reason:'opening',lines:[{productId:product.id,batch:'REAL',expiry:'2030-12-31',quantity:20}]});
  await call('POST','/v1/sync/status',{body:{operations:[receipt]}});assert.equal((await push(receipt)).status,'accepted');
  await call('POST','/v1/sync/status',{body:{operations:[receipt]}});
  const lot=await owner.inventoryLot.findFirstOrThrow({where:{storeId:store}}),saleId=randomUUID(),lineId=randomUUID();
  await push(envelope({type:'sale.create',saleId,occurredAt:new Date().toISOString(),lines:[{id:lineId,productId:product.id,quantity:2,unitPriceMillimes:'12345',allocations:[{lotId:lot.id,quantity:2}]}]}));
  await call('GET',`${storeUrl}/sales/${saleId}?${scope}`);
  for(const resource of ['sales','points','movements','audit'])await call('GET',`${storeUrl}/history/${resource}?${scope}`);
  for(const resource of ['lots','config','products','sales','points','audit'])await call('GET',`${storeUrl}/collections/${resource}?${scope}`);
  const reward=await call('POST',`${storeUrl}/rewards?${scope}`,{body:{title:'Contract gift',description:'Fixture',cost:10,productId:product.id,quantity:1,active:true}});
  const claim=randomUUID();await push(envelope({type:'reward.request',claimId:claim,rewardId:reward.id}));await push(envelope({type:'reward.resolve',claimId:claim,decision:'fulfilled'},1));
  const orderId=randomUUID(),deliveryId=randomUUID();await push(envelope({type:'order.create',orderId,lines:[{productId:product.id,quantity:5}]}));
  await push(envelope({type:'order.prepare',orderId},1),adminToken);
  const dispatched=await push(envelope({type:'delivery.dispatch',orderId,deliveryId,lines:[{productId:product.id,quantity:5}]},2),adminToken);
  assert.equal(dispatched.data.version,1);assert(dispatched.affectedVersions.some(v=>v.resource==='deliveries'&&v.version===1));
  await push(envelope({type:'delivery.receive',deliveryId,lines:[{productId:product.id,batch:'DELIVERY',expiry:'2031-01-31',quantity:3}],note:'Two missing'},1));
  await call('GET',`${storeUrl}/orders/${orderId}/fulfillment?${scope}`);
  await call('GET',`${storeUrl}/ranking?${scope}`);await call('GET',`${storeUrl}/changes?${scope}`);
  await owner.inventoryLot.createMany({data:Array.from({length:501},(_,i)=>({organizationId:org,storeId:store,productId:product.id,batch:`PAGE-${i}`,expiry:new Date('2030-01-31'),sellable:1}))});
  const snapshot=await call('GET',`${storeUrl}/snapshot?${scope}&protocol=3`);
  assert(snapshot.snapshotPages.lots);await call('GET',`${storeUrl}/snapshot-pages/${snapshot.snapshotPages.lots}?${scope}`);
  await call('GET',`${storeUrl}/snapshot?${scope}&protocol=3&after=${snapshot.cursor}&catalogRevision=${snapshot.catalogRevision}`);
  await call('POST',`${storeUrl}/announcements?${scope}`,{body:{id:randomUUID(),title:'Formation disponible',body:'Consultez les conseils',audience:'all'}});
  const notifications=await call('GET','/v1/notifications');assert(notifications.length);await call('GET',`/v1/notifications/${notifications[0].id}`);await call('PATCH',`/v1/notifications/${notifications[0].id}/read`);
  const deviceToken='test-device-'+randomUUID();await call('POST','/v1/devices',{body:{token:deviceToken,platform:'android'}});await call('DELETE','/v1/devices',{body:{token:deviceToken,platform:'android'},status:200});
  const training=await call('POST','/v1/training',{as:adminToken,body:{id:randomUUID(),submissionId:randomUUID(),expectedVersion:0,title:'Training fixture',body:'<p>Conseils</p>',type:'article',productIds:[product.id],status:'published'}});
  await call('GET','/v1/training');await call('GET',`/v1/training/${training.id}`);
  const image=await readFile(path.resolve(__dirname,'../../mobile/assets/brand/biobalance-logo.jpg'));
  const upload=await call('POST','/v1/media/uploads',{as:adminToken,body:{fileName:'fixture.png',mime:'image/png',size:image.length,sha256:createHash('sha256').update(image).digest('hex'),purpose:'catalog'}});
  await call('PUT',`/v1/media/uploads/${upload.id}`,{as:adminToken,body:image,headers:{'Upload-Offset':'0'},status:200});
  await new MediaProcessor(app.get(Database),root).process(upload.id);
  await call('GET',`/v1/media/uploads/${upload.id}`,{as:adminToken});await call('GET',`/v1/media/${upload.id}/metadata`,{as:adminToken});
  await call('GET',`/v1/media/${upload.id}`,{as:adminToken});await call('GET',`/v1/media/${upload.id}`,{as:adminToken,headers:{Range:'bytes=10-'},status:206});
  await call('GET','/v1/admin/overview',{as:adminToken});await call('GET','/v1/reports/overview',{as:adminToken});await call('GET',`/v1/reports/stores/${store}/sales.csv?${scope}`);
  await call('POST','/v1/identity/logout');
  const missing=routes.map(r=>r.spec.operationId).filter(id=>!seen.has(id));assert.deepEqual(missing,[],'Every route needs a successful HTTP contract example');
  const fixturePath=path.join(root,'contract-fixtures.json');await writeFile(fixturePath,JSON.stringify(fixtures));
  const {spawn}=require('node:child_process');
  const exit=await new Promise((resolve,reject)=>{const child=spawn(process.env.FLUTTER_BIN??'flutter',['test','test/transport_api_contract_test.dart','--reporter','expanded'],{cwd:path.resolve(__dirname,'../../mobile'),stdio:'inherit',env:{...process.env,BIOBALANCE_CONTRACT_FIXTURE:fixturePath}});child.on('error',reject);child.on('exit',resolve);});
  assert.equal(exit,0,'Dart transport must decode and preserve the actual HTTP fixtures');
  console.log(`PASS: ${seen.size} HTTP endpoint contracts, all request/response schemas, snapshots/pages, exact money, delivery versions, protected image ranges.`);
 } finally {await app.close();await owner.$disconnect();await rm(root,{recursive:true,force:true});}
})().catch(error=>{console.error(error);process.exitCode=1;});
