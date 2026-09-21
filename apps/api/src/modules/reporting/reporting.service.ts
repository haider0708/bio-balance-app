import {Injectable} from '@nestjs/common';
import {Actor} from '../operations/domain/contracts';
import {WorkspaceService} from '../tenancy/workspace.service';
import {Database} from '../../shared/infrastructure/database';
import {requireRule} from '../../shared/domain/errors';
@Injectable()
export class ReportingService {
 constructor(private readonly db:Database,private readonly workspace:WorkspaceService){}
 async overview(actor:Actor) {
  requireRule(actor.platformAdmin,'FORBIDDEN','Accès réservé à BioBalance.',403);
  const stores=await this.workspace.stores(actor);
  return {stores,totalStores:stores.length,organizations:await this.db.organization.count(),staff:await this.db.user.count({where:{disabled:false}})};
 }
 async salesCsv(actor:Actor,organizationId:string,storeId:string,after?:string) {
  const rows=await this.workspace.list(actor,organizationId,storeId,'sales',after);
  const cell=(v:unknown)=>`"${String(v??'').replace(/^[=+@-]/,"'$&").replace(/"/g,'""')}"`;
  const lines=rows.map(row=>{
   const sale=row as {id:string;occurredAt:Date;sellerId:string;totalMillimes:bigint;earnedPoints:bigint};
   return [sale.id,sale.occurredAt.toISOString(),sale.sellerId,sale.totalMillimes,sale.earnedPoints].map(cell).join(';');
  });
  return '\uFEFFIdentifiant;Date;Vendeur;Total en millimes;Points\n'+lines.join('\n');
 }
}
