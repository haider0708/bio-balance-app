set -e
cd /home/haydar/Documents/ChatGPT/BIOBALANCE
P="docker exec -i biobalance-dev-postgres-1 psql -U biobalance -v ON_ERROR_STOP=1"
$P -d postgres -c 'DROP DATABASE IF EXISTS rehearsal_test' -c 'CREATE DATABASE rehearsal_test' >/dev/null
(cd apps/api && DATABASE_URL=postgresql://biobalance:local-development-only@localhost:54329/rehearsal_test npx prisma migrate deploy >/dev/null 2>&1)
$P -d rehearsal_test -v app_password=local-app-only -f - < scripts/provision-role.sql >/dev/null 2>&1
$P -d rehearsal_test -c "insert into \"User\"(id,email,name,\"passwordHash\",\"platformAdmin\") select gen_random_uuid(),e,n,'x',a from (values ('boudhriwa.haydar@gmail.com','BioBalance',true),('haydar.boudhrioua@gmail.com','RESPONSABLE PARAHOUSE',false),('hayder.boudhrioua@gmail.com','SAMIR',false),('besel62147@caps7.com','IMED',false),('hayder@tanpony.com','HEDI',false)) v(e,n,a)" -c "insert into \"Product\"(id,reference,name,category,\"updatedAt\") select gen_random_uuid(),'REF'||lpad(i::text,3,'0'),'Produit '||i,(array['Sérums','Sérums','Nettoyants visage','Maquillage','Crèmes visage','Soins capillaires','Soins personnels'])[1+i%7],now() from generate_series(1,51) i" >/dev/null
$P -d rehearsal_test -f - < /tmp/claude-1000/seed/structure.sql | tail -3
cd apps/api
export PATH=/tmp/claude-1000/ffbin:$PATH
DIST=$PWD/dist DATABASE_URL=postgresql://biobalance_app:local-app-only@localhost:54329/rehearsal_test timeout 500 node /tmp/claude-1000/seed/seed.cjs 2>&1 | tail -30
