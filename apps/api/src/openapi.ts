import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { SwaggerModule,DocumentBuilder } from '@nestjs/swagger';
import { writeFileSync } from 'node:fs';
import { AppModule } from './app.module';
import { applyContract } from './shared/contracts/api-contract';
export async function contract() {
 const app=await NestFactory.create(AppModule,{logger:false});
 try{return applyContract(SwaggerModule.createDocument(app,new DocumentBuilder().setTitle('BioBalance API').setDescription('API v1. Contexte compte et magasin vérifié côté serveur. TND en millimes entiers exacts. Commandes idempotentes, historique et payloads v1 conservés.').setVersion('1.0.0').addBearerAuth().build()));}
 finally{await app.close();}
}
if(require.main===module)void contract().then(document=>writeFileSync('../../contracts/openapi/biobalance.json',JSON.stringify(document,null,2)+'\n'));
