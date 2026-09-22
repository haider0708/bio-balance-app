const assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path');
const {randomUUID,createHash}=require('node:crypto');
const {execFileSync}=require('node:child_process');
const {URI}=require('otpauth');
const lab=path.resolve('.artifacts/deployment-lab'),base='https://localhost:18443';
const sha=b=>createHash('sha256').update(b).digest('hex');
const wait=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
 const fixture=JSON.parse(await fs.readFile(path.join(lab,'fixture.json')));
 const setup=JSON.parse(await fs.readFile(path.join(lab,'bootstrap/credentials.json')));
 let token=fixture.managerToken;
 const call=async(method,url,body,as=token,expected=method==='POST'?201:200,extra={})=>{
  const response=await fetch(base+url,{method,headers:{...(as?{Authorization:`Bearer ${as}`} : {}),...(body?{'Content-Type':Buffer.isBuffer(body)?'application/octet-stream':'application/json'}:{}),...extra},...(body?{body:Buffer.isBuffer(body)?body:JSON.stringify(body)}:{})});
  const mime=response.headers.get('content-type')??'';
  const data=mime.includes('json')?await response.json():Buffer.from(await response.arrayBuffer());
  assert.equal(response.status,expected,`${method} ${url.split('?')[0]} status ${response.status}: ${data.code??''}`);
  return {data,response};
 };
 // Consecutive probes must respect the server's one-use MFA counter.
 const authenticator=URI.parse(setup.totpUri),period=authenticator.period*1000;
 const stepFile=path.join(lab,'admin-login-step');
 let previous=-1;
 try {previous=Number(await fs.readFile(stepFile,'utf8'));}
 catch(error){if(error.code!=='ENOENT')throw error;}
 assert(Number.isSafeInteger(previous));
 const delay=(previous+1)*period-Date.now()+250;
 assert(delay<=period+1000,'Invalid deployment probe clock');
 if(delay>0)await wait(delay);
 const loginStep=Math.floor(Date.now()/period);
 const login=await call('POST','/v1/identity/login',{email:setup.email,password:setup.password,otp:authenticator.generate()},null);
 await fs.writeFile(stepFile,String(loginStep),{mode:0o600});
 const admin=login.data.token;
 let state;
 if(process.argv[2]==='verify') state=JSON.parse(await fs.readFile(path.join(lab,'state.json')));
 else {
  const store=(await call('POST','/v1/stores',{organizationId:fixture.organizationId,name:'Deployment validation',address:'Adresse de test',city:'Tunis'})).data;
  const scoped=`/v1/stores/${store.id}`,scope=`organizationId=${fixture.organizationId}`;
  const product=(await call('POST','/v1/catalog/products',{reference:'DEPLOY-'+randomUUID(),name:'Produit de test',active:true},admin)).data;
  await call('PATCH',`${scoped}/products/${product.id}?${scope}`,{priceMillimes:'49900',threshold:5,pointsPerUnit:10});
  const envelope=command=>({operationId:randomUUID(),organizationId:fixture.organizationId,storeId:store.id,payloadVersion:2,dependencies:[],command});
  const push=async operation=>{const result=(await call('POST','/v1/sync/push',{operations:[operation]})).data.results[0];assert.equal(result.status,'accepted');return result;};
  await push(envelope({type:'stock.receive',reason:'opening',lines:[{productId:product.id,batch:'DEPLOY',expiry:'2030-12-31',quantity:10}]}));
  const first=(await call('GET',`${scoped}/snapshot?${scope}&protocol=3`)).data;
  const lot=first.lots[0];
  const sale=envelope({type:'sale.create',saleId:randomUUID(),occurredAt:new Date().toISOString(),lines:[{id:randomUUID(),productId:product.id,quantity:6,unitPriceMillimes:'49900',allocations:[{lotId:lot.id,quantity:6}]}]});
  await push(sale);await push(sale);
  const imagePath=path.join(lab,'source.png'),videoPath=path.join(lab,'source.mp4');
  execFileSync('ffmpeg',['-nostdin','-y','-v','error','-f','lavfi','-i','color=c=0x6ABE4E:s=1920x1080','-frames:v','1','-threads','1',imagePath]);
  execFileSync('ffmpeg',['-nostdin','-y','-v','error','-f','lavfi','-i','testsrc2=size=320x180:rate=24','-t','4','-c:v','libx264','-threads','1','-pix_fmt','yuv420p',videoPath]);
  const upload=async(file,mime,purpose,as,ownership={})=>{
   const bytes=await fs.readFile(file);
   const started=(await call('POST','/v1/media/uploads',{fileName:path.basename(file),mime,size:bytes.length,sha256:sha(bytes),purpose,...ownership},as)).data;
   const end=Math.min(1000,bytes.length);
   await call('PUT',`/v1/media/uploads/${started.id}`,bytes.subarray(0,end),as,200,{'Upload-Offset':'0'});
   await call('PUT',`/v1/media/uploads/${started.id}`,bytes.subarray(end),as,200,{'Upload-Offset':String(end)});
   // Repeat the last chunk after a potentially lost response.
   await call('PUT',`/v1/media/uploads/${started.id}`,bytes.subarray(end),as,200,{'Upload-Offset':String(end)});
   let status;
   for(let attempt=0;attempt<120;attempt++){
    status=(await call('GET',`/v1/media/uploads/${started.id}`,undefined,as)).data;
    if(status.status==='ready')break;
    assert.notEqual(status.status,'failed','media processing failed');await wait(500);
   }
   assert.equal(status.status,'ready','worker must process the upload');
   return started.id;
  };
  const image=await upload(imagePath,'image/png','store',token,{organizationId:fixture.organizationId,storeId:store.id});
  await call('PATCH',`${scoped}?${scope}`,{name:store.name,address:store.address,city:store.city,phone:null,imageId:image,expectedVersion:1});
  const video=await upload(videoPath,'video/mp4','training',admin);
  const training=(await call('POST','/v1/training',{id:randomUUID(),submissionId:randomUUID(),expectedVersion:0,title:'Vidéo de test',body:'<p>Validation</p>',type:'video',mediaId:video,productIds:[product.id],status:'published'},admin)).data;
  state={store:store.id,product:product.id,lot:lot.id,sale,image,video,training:training.id};
  await fs.writeFile(path.join(lab,'state.json'),JSON.stringify(state),{mode:0o600});
 }
 const scope=`organizationId=${fixture.organizationId}`;
 const snapshot=(await call('GET',`/v1/stores/${state.store}/snapshot?${scope}&protocol=3`)).data;
 assert.equal(snapshot.lots.find(l=>l.id===state.lot).sellable,4);
 assert.equal(snapshot.lots.find(l=>l.id===state.lot).version,3);
 assert.equal(snapshot.points.balance,'60');
 assert.equal(snapshot.sales.filter(s=>s.id===state.sale.command.saleId).length,1);
 assert(snapshot.alerts.some(a=>a.kind==='low'));
 const replay=(await call('POST','/v1/sync/push',{operations:[state.sale]})).data.results[0];assert.equal(replay.status,'accepted');
 await call('GET',`/v1/media/${state.image}`,undefined,fixture.outsiderToken,403);
 await call('GET',`/v1/stores/${state.store}/snapshot?${scope}`,undefined,fixture.outsiderToken,403);
 for(const id of [state.image,state.video]){
  const meta=(await call('GET',`/v1/media/${id}/metadata`)).data;
  const {data:bytes,response}=await call('GET',`/v1/media/${id}`);
  assert.equal(sha(bytes),meta.sha256);assert.equal(String(bytes.length),String(meta.size));
  assert.equal(response.headers.get('x-content-sha256'),meta.sha256);
  const partial=await call('GET',`/v1/media/${id}`,undefined,token,206,{Range:'bytes=10-99','If-Range':response.headers.get('etag')});
  assert.equal(partial.data.length,90);assert(partial.data.equals(bytes.subarray(10,100)));
  assert.equal(partial.response.headers.get('content-range'),`bytes 10-99/${bytes.length}`);
  await call('GET',`/_media/${id}.${id===state.image?'png':'mp4'}`,undefined,null,404);
 }
 await call('GET',`/v1/training/${state.training}`);
 console.log('PASS: HTTPS, restricted store access, receipt/sale/replay, stock 4 v3, points 60, processed image/video, SHA-256 and protected ranges.');
})().catch(error=>{console.error(error);process.exitCode=1});
