const {execFileSync}=require('node:child_process'),assert=require('node:assert/strict'),path=require('node:path');
const root=process.cwd(),lab=path.join(root,'.artifacts/deployment-lab');
const args=['compose','-f',path.join(root,'infrastructure/production/compose.yml'),'--env-file',path.join(lab,'.env'),'-f',path.join(lab,'override.yml'),'-p','biobalance-release-lab'];
for(const service of ['api1','api2','worker','media-worker','postgres']){
 const id=execFileSync('docker',[...args,'ps','-q',service],{encoding:'utf8'}).trim();assert(id);
 const container=JSON.parse(execFileSync('docker',['inspect',id],{encoding:'utf8'}))[0];
 const env=Object.fromEntries(container.Config.Env.map(entry=>{const i=entry.indexOf('=');return [entry.slice(0,i),entry.slice(i+1)]}));
 if(service!=='postgres'){
  assert(!('POSTGRES_PASSWORD' in env));assert(!('MIGRATION_DATABASE_URL' in env));
  assert.equal(new URL(env.DATABASE_URL).username,'biobalance_app');
  assert.equal(container.Config.User,'node');assert.equal(container.HostConfig.ReadonlyRootfs,true);
 }
 if(service==='media-worker'||service.startsWith('api')){
  assert(!('SMTP_PASSWORD' in env));assert(!container.Mounts.some(m=>m.Destination.includes('firebase')));
 }
 if(service==='media-worker')assert(!('MFA_ENCRYPTION_KEY' in env));
 if(service==='worker')assert(!container.Mounts.some(m=>m.Destination==='/var/lib/biobalance/media'));
 if(service==='postgres')assert(!Object.values(container.NetworkSettings.Ports).some(Boolean));
 if(service==='media-worker')assert.equal(container.Config.StopTimeout,660);
 console.log(`PASS: ${service} environment, identity and exposure`);
}
const appProbe=`const {Database}=require('./dist/shared/infrastructure/database');const db=new Database();(async()=>{const [r]=await db.$queryRawUnsafe('SELECT current_user AS name,rolsuper,rolbypassrls FROM pg_roles WHERE rolname=current_user');if(r.name!=='biobalance_app'||r.rolsuper||r.rolbypassrls)throw Error('privileged role');if((await db.inventoryLot.findMany()).length)throw Error('missing RLS context leaked rows');console.log('PASS: runtime database identity and RLS isolation')})().finally(()=>db.$disconnect());`;
process.stdout.write(execFileSync('docker',[...args,'exec','-T','api1','node','-e',appProbe],{encoding:'utf8'}));
execFileSync('docker',[...args,'exec','-T','worker','test','-r','/run/secrets/firebase-service-account.json']);
console.log('PASS: only the notification worker can read its mounted provider file');
