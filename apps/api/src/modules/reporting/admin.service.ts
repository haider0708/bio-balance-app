import { Injectable } from '@nestjs/common';
import { Database } from '../../shared/infrastructure/database';
import { Actor } from '../operations/domain/contracts';
import { requireRule } from '../../shared/domain/errors';
@Injectable()
export class AdminService {
 constructor(private readonly db:Database){}
 overview(actor:Actor){return this.db.$transaction(async tx=>{
  const user=await tx.user.findUnique({where:{id:actor.id}});requireRule(user?.platformAdmin&&!user.disabled,'FORBIDDEN','Accès réservé à BioBalance.',403);
  await tx.$executeRaw`SELECT set_config('app.admin_read','true',true)`;
  const [stores,staff,orders,alerts]=await Promise.all([tx.store.findMany({orderBy:{name:'asc'},take:1000}),tx.user.count({where:{disabled:false}}),tx.replenishmentOrder.findMany({where:{status:{not:'received'}},orderBy:{createdAt:'asc'},take:100}),tx.alert.findMany({where:{active:true},orderBy:{createdAt:'desc'},take:200})]);
  await tx.auditEntry.create({data:{actorId:actor.id,action:'admin.overview.read',targetId:'platform',details:{stores:stores.length}}});
  return {storeCount:stores.length,staffCount:staff,orders:orders.map(o=>({...o,storeName:stores.find(s=>s.id===o.storeId)?.name})),alerts:alerts.map(a=>({...a,storeName:stores.find(s=>s.id===a.storeId)?.name}))};
 });}
}
