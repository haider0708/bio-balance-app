const fs = require('node:fs');
const { randomUUID } = require('node:crypto');
const assert = require('node:assert/strict');
const fixture = JSON.parse(fs.readFileSync('.artifacts/deployment-lab/fixture.json'));
const state = JSON.parse(fs.readFileSync('.artifacts/deployment-lab/state.json'));
const headers = { Authorization: `Bearer ${fixture.managerToken}`, 'Content-Type': 'application/json' };
const base = 'https://localhost:18443';
(async () => {
 const today = new Date(Date.now() + 3600000).toISOString().slice(0,10);
 const query = {scope:'store',organizationId:fixture.organizationId,storeId:state.store,from:today.slice(0,4)+'-01-01',to:today};
 const dashboard = await fetch(base+'/v1/dashboards?'+new URLSearchParams(query),{headers});
 assert.equal(dashboard.status,200); const data=await dashboard.json(); assert(BigInt(data.saleCount)>0n);
 const id=randomUUID();
 const created=await fetch(base+'/v1/report-exports',{method:'POST',headers,body:JSON.stringify({id,query})});
 assert.equal(created.status,201);
 let item;
 for(let n=0;n<60;n++){
  const status=await fetch(base+`/v1/report-exports/${id}`,{headers});assert.equal(status.status,200);item=await status.json();
  if(item.status==='ready')break;
  assert.notEqual(item.status,'failed');await new Promise(r=>setTimeout(r,500));
 }
 assert.equal(item.status,'ready','worker must prepare the complete export');
 const file=await fetch(base+`/v1/report-exports/${id}/file`,{headers});assert.equal(file.status,200);assert((await file.text()).includes('TND'));
 const forbidden=await fetch(base+`/v1/report-exports/${id}/file`);assert.equal(forbidden.status,401);
 console.log('PASS: scoped projections, real export worker, shared protected download volume and unauthorized denial.');
})().catch(e=>{console.error(e);process.exitCode=1});
