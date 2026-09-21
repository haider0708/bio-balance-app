const assert=require('node:assert/strict'),{spawn,execFileSync}=require('node:child_process'),fs=require('node:fs'),path=require('node:path');
const root=process.cwd(),lab=path.join(root,'.artifacts/deployment-lab');
const fixture=JSON.parse(fs.readFileSync(path.join(lab,'fixture.json'))),state=JSON.parse(fs.readFileSync(path.join(lab,'state.json')));
const apiImage=process.env.TARGET_API_IMAGE,mediaImage=process.env.TARGET_MEDIA_IMAGE;
assert(apiImage&&mediaImage,'explicit tested rollback/update images required');
const args=['compose','-f',path.join(root,'infrastructure/production/compose.yml'),'--env-file',path.join(lab,'.env'),'-f',path.join(lab,'override.yml'),'-p','biobalance-release-lab'];
const env={...process.env,API_IMAGE:apiImage,MEDIA_IMAGE:mediaImage};
const probe=async()=>{
 const response=await fetch(`https://localhost:18443/v1/stores/${state.store}/snapshot?organizationId=${fixture.organizationId}&protocol=3`,{headers:{Authorization:`Bearer ${fixture.managerToken}`}});
 assert.equal(response.status,200);const body=await response.json();assert.equal(body.lots.find(l=>l.id===state.lot).sellable,4);assert.equal(body.points.balance,'60');
};
(async()=>{
 let reads=0;
 for(const services of [['api1'],['api2'],['worker','media-worker']]){
  let done=false;
  const child=spawn('docker',[...args,'up','-d','--no-deps','--force-recreate','--wait',...services],{env,stdio:['ignore','inherit','inherit']});
  const complete=new Promise((resolve,reject)=>{child.on('error',reject);child.on('exit',code=>{done=true;code===0?resolve():reject(Error(`restart failed: ${code}`))})});
  while(!done){await probe();reads++;await new Promise(r=>setTimeout(r,200))}
  await complete;
  for(const service of services){
   const id=execFileSync('docker',[...args,'ps','-q',service],{env,encoding:'utf8'}).trim();
   const actual=JSON.parse(execFileSync('docker',['inspect',id],{encoding:'utf8'}))[0].Image;
   const expected=JSON.parse(execFileSync('docker',['image','inspect',service==='media-worker'?mediaImage:apiImage],{encoding:'utf8'}))[0].Id;
   assert.equal(actual,expected);
  }
 }
 console.log(`PASS: rolling change to ${apiImage}; ${reads} authorized reads preserved stock and points during API/worker replacement.`);
})().catch(error=>{console.error(error);process.exitCode=1});
