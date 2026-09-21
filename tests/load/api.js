import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';
const fixtures=JSON.parse(open(__ENV.FIXTURES));
const base=__ENV.BASE_URL||'http://localhost:3000';
const rejected=new Counter('rejected_operations');
export const options={
  scenarios:{steady:{executor:'constant-arrival-rate',rate:100,timeUnit:'1s',duration:'5m',preAllocatedVUs:50,maxVUs:200},
    burst:{executor:'constant-arrival-rate',rate:200,timeUnit:'1s',duration:'30s',startTime:'5m',preAllocatedVUs:80,maxVUs:300}},
  thresholds:{'http_req_duration{kind:read}':['p(95)<300'],'http_req_duration{kind:write}':['p(95)<700'],http_req_failed:['rate<0.001'],rejected_operations:['count==0'],dropped_iterations:['count==0']},
};
function uuid(){return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const r=Math.random()*16|0;return(c==='x'?r:(r&3|8)).toString(16);});}
export default function(){
  const f=fixtures[(__VU+__ITER)%fixtures.length];
  const headers={Authorization:`Bearer ${f.token}`,'Content-Type':'application/json'};
  if(__ITER%10){
    const response=http.get(`${base}/v1/stores/${f.storeId}/snapshot?organizationId=${f.organizationId}&after=0&catalogRevision=${f.catalogRevision}`,{headers,tags:{kind:'read'}});
    check(response,{'read accepted':r=>r.status===200});
  }else{
    const operation={operationId:uuid(),organizationId:f.organizationId,storeId:f.storeId,payloadVersion:1,
      command:{type:'sale.create',saleId:uuid(),occurredAt:new Date().toISOString(),lines:[{id:uuid(),productId:f.productId,quantity:1,unitPriceMillimes:'49900',allocations:[{lotId:f.lotId,quantity:1}]}]}};
    const response=http.post(`${base}/v1/sync/push`,JSON.stringify({operations:[operation]}),{headers,tags:{kind:'write'}});
    const accepted=response.status===201&&response.json('results.0.status')==='accepted';
    check(response,{'write accepted':()=>accepted});if(!accepted)rejected.add(1);
  }
}
