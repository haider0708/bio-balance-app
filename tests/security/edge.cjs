/* Exercise the real isolated Nginx/TLS boundary, without opening API ports. */
const https=require('node:https'),fs=require('node:fs'),assert=require('node:assert/strict');
const ca=fs.readFileSync('.artifacts/deployment-lab/certificates/fullchain.pem');
function get(path, options={}) {
  return new Promise((resolve,reject)=>{
    const request=https.get({hostname:'localhost',port:18443,path,ca,rejectUnauthorized:true,...options},response=>{
      let body='';response.on('data',b=>body+=b);response.on('end',()=>resolve({status:response.statusCode,headers:response.headers,body}));
    });request.on('error',reject);
  });
}
(async()=>{
  for(const version of ['TLSv1.2','TLSv1.3']) assert.equal((await get('/health',{minVersion:version,maxVersion:version})).status,200);
  await assert.rejects(get('/health',{minVersion:'TLSv1.1',maxVersion:'TLSv1.1'}));
  await assert.rejects(get('/health',{ca:[],agent:false}));
  const privateMedia=await get('/_media/anything');assert.equal(privateMedia.status,404);
  const health=await get('/health');assert.equal(health.headers['cache-control'],'no-store');assert(health.headers['strict-transport-security']);
  const statuses=[];
  for(let wave=0;wave<18;wave++){
    const batch=await Promise.all(Array.from({length:24},()=>get('/v1/security-rate-probe')));statuses.push(...batch);
  }
  const throttled=statuses.filter(r=>r.status===429);assert(throttled.length>0,'Expected shared-IP burst protection');
  for(const response of throttled){assert.equal(JSON.parse(response.body).code,'RATE_LIMITED');assert(Number(response.headers['retry-after'])>0);}
  const identity=await Promise.all(Array.from({length:24},()=>get('/V1/IDENTITY/not-a-route')));
  assert(identity.some(r=>r.status===429),'Identity limits must cover case variants');
  assert.equal((await get('/v1/identity/not-a-route')).status,429,'Case variants must share the same IP budget');
  await new Promise(r=>setTimeout(r,2200));
  assert.equal((await get('/v1/identity/logout',{method:'POST'})).status,401,'Logout must reach authentication despite the exhausted identity IP budget');
  console.log(JSON.stringify({passed:['TLS 1.2/1.3','TLS 1.1 refused','untrusted certificate refused','private media denied','no-store and HSTS','JSON 429 with Retry-After','case-insensitive identity limits','logout independent of identity limits'],requests:statuses.length,throttled:throttled.length}));
})().catch(error=>{console.error(error.message);process.exitCode=1;});
