const fs=require('node:fs'),{randomUUID}=require('node:crypto'),assert=require('node:assert/strict');
const fixture=JSON.parse(fs.readFileSync('.artifacts/deployment-lab/fixture.json')),state=JSON.parse(fs.readFileSync('.artifacts/deployment-lab/state.json'));
(async()=>{
 const email=`mail-${randomUUID()}@example.test`;
 const response=await fetch('https://localhost:18443/v1/identity/invitations',{method:'POST',headers:{Authorization:`Bearer ${fixture.managerToken}`,'Content-Type':'application/json'},body:JSON.stringify({email,organizationId:fixture.organizationId,storeId:state.store,permissions:['sell']})});
 assert.equal(response.status,201);
 let found=false;
 for(let n=0;n<30;n++){
  const inbox=await(await fetch('http://127.0.0.1:18025/api/v1/messages')).json();
  found=inbox.messages.some(m=>m.To.some(to=>to.Address===email));
  if(found)break;await new Promise(r=>setTimeout(r,500));
 }
 assert(found,'local SMTP worker must deliver the invitation');console.log('PASS: invitation delivered by the worker to isolated Mailpit');
})().catch(error=>{console.error(error);process.exitCode=1});
