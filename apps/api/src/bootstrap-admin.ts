import 'reflect-metadata';
import {randomBytes,randomUUID} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import argon2 from 'argon2';
import {Secret,TOTP} from 'otpauth';
import {Database} from './shared/infrastructure/database';
import {encryptSecret} from './modules/identity/identity.service';
import {z} from 'zod';
async function main(){
  const email=z.email().parse(process.env.ADMIN_EMAIL).trim().toLowerCase();
  const output=z.string().min(1).parse(process.env.ADMIN_SETUP_FILE);
  const db=new Database();
  try {
    if(await db.user.findFirst({where:{platformAdmin:true}}))throw new Error('An administrator already exists. Use account recovery.');
    const id=randomUUID(),password=randomBytes(24).toString('base64url'),secret=new Secret({size:20});
    const uri=new TOTP({issuer:'BioBalance',label:email,secret,algorithm:'SHA1',digits:6,period:30}).toString();
    // Exclusive creation prevents overwriting existing recovery material.
    await writeFile(output,JSON.stringify({email,password,totpUri:uri},null,2),{mode:0o600,flag:'wx'});
    await db.$transaction(async tx=>{
      await tx.user.create({data:{id,email,name:process.env.ADMIN_NAME??'BioBalance',passwordHash:await argon2.hash(password,{type:argon2.argon2id}),platformAdmin:true,mfaSecret:encryptSecret(secret.hex)}});
      await tx.auditEntry.create({data:{actorId:id,action:'admin.bootstrap',targetId:id,details:{localProvisioning:true}}});
    });
    console.log('Administrator created. Import the authenticator URI and store the private setup file securely.');
  }finally{await db.$disconnect();}
}
void main().catch(()=>{console.error('Administrator provisioning failed; check configuration and the private setup file.');process.exitCode=1;});
