import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
} from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { StructureService } from "./structure.service";
import { UsersService } from "./users.service";

const id = z.uuid();
const text = (max = 120) => z.string().trim().min(1).max(max);
const email = z.string().trim().toLowerCase().pipe(z.email());
const phone = z.string().trim().max(30).nullable().optional();
const Status = z.enum(["PENDING", "ACTIVE", "REJECTED", "SUSPENDED"]);
const Note = z.object({ note: z.string().trim().max(500).optional() });

const Group = z.object({ name: text() });
const Pdv = z.object({
  name: text(),
  address: text(200),
  city: text(80),
  phone,
  groupId: id.nullable().optional(),
});
const Member = z.object({ name: text(100), email, phone });
const AdminUser = z.discriminatedUnion("role", [
  z.object({
    role: z.literal("RESPONSABLE"),
    regionId: id,
    name: text(100),
    email,
    phone,
  }),
  z.object({
    role: z.literal("GROSSISTE"),
    name: text(100),
    email,
    phone,
    depot: z.object({
      name: text(),
      address: text(200),
      city: text(80),
      phone,
    }),
  }),
  z.object({
    role: z.literal("VENDEUR"),
    pdvId: id,
    name: text(100),
    email,
    phone,
  }),
]);
const UserPatch = z.object({
  name: text(100).optional(),
  phone,
  pdvId: id.optional(),
});
const DepotPatch = z.object({
  name: text().optional(),
  address: text(200).optional(),
  city: text(80).optional(),
  phone,
});

@Controller("v1")
export class DirectoryController {
  constructor(
    private readonly structure: StructureService,
    private readonly users: UsersService,
  ) {}

  @Get("regions") regions() {
    return this.structure.regions();
  }

  // Groups
  @Roles("RESPONSABLE")
  @Post("groups")
  createGroup(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.structure.createGroup(r.actor, parse(Group, b));
  }
  @Roles("ADMIN", "RESPONSABLE")
  @Get("groups")
  groups(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.structure.listGroups(
      r.actor,
      parse(
        z.object({ status: Status.optional(), regionId: id.optional() }),
        q,
      ),
    );
  }
  @Roles("ADMIN", "RESPONSABLE")
  @Patch("groups/:id")
  updateGroup(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.structure.updateGroup(r.actor, parse(id, i), parse(Group, b));
  }
  @Roles("ADMIN")
  @Post("groups/:id/approve")
  approveGroup(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.structure.decideGroup(
      r.actor,
      parse(id, i),
      "approve",
      parse(Note, b ?? {}).note,
    );
  }
  @Roles("ADMIN")
  @Post("groups/:id/reject")
  rejectGroup(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.structure.decideGroup(
      r.actor,
      parse(id, i),
      "reject",
      parse(Note, b ?? {}).note,
    );
  }
  @Roles("ADMIN")
  @Post("groups/:id/suspend")
  suspendGroup(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.structure.decideGroup(
      r.actor,
      parse(id, i),
      "suspend",
      parse(Note, b ?? {}).note,
    );
  }
  @Roles("ADMIN")
  @Post("groups/:id/reactivate")
  reactivateGroup(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.structure.decideGroup(r.actor, parse(id, i), "reactivate");
  }
  @Roles("RESPONSABLE")
  @Post("groups/:id/resubmit")
  resubmitGroup(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.structure.decideGroup(r.actor, parse(id, i), "resubmit");
  }

  // Points of sale
  @Roles("RESPONSABLE")
  @Post("pdvs")
  createPdv(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.structure.createPdv(r.actor, parse(Pdv, b));
  }
  @Roles("ADMIN", "RESPONSABLE", "VENDEUR")
  @Get("pdvs")
  pdvs(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.structure.listPdvs(
      r.actor,
      parse(
        z.object({
          status: Status.optional(),
          regionId: id.optional(),
          groupId: id.optional(),
          q: z.string().max(80).optional(),
        }),
        q,
      ),
    );
  }
  @Roles("ADMIN", "RESPONSABLE", "VENDEUR")
  @Get("pdvs/:id")
  pdv(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.structure.getPdv(r.actor, parse(id, i));
  }
  @Roles("ADMIN", "RESPONSABLE")
  @Patch("pdvs/:id")
  updatePdv(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.structure.updatePdv(
      r.actor,
      parse(id, i),
      parse(Pdv.partial(), b),
    );
  }
  @Roles("ADMIN")
  @Post("pdvs/:id/approve")
  approvePdv(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.structure.decidePdv(
      r.actor,
      parse(id, i),
      "approve",
      parse(Note, b ?? {}).note,
    );
  }
  @Roles("ADMIN")
  @Post("pdvs/:id/reject")
  rejectPdv(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.structure.decidePdv(
      r.actor,
      parse(id, i),
      "reject",
      parse(Note, b ?? {}).note,
    );
  }
  @Roles("ADMIN")
  @Post("pdvs/:id/suspend")
  suspendPdv(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.structure.decidePdv(
      r.actor,
      parse(id, i),
      "suspend",
      parse(Note, b ?? {}).note,
    );
  }
  @Roles("ADMIN")
  @Post("pdvs/:id/reactivate")
  reactivatePdv(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.structure.decidePdv(r.actor, parse(id, i), "reactivate");
  }
  @Roles("RESPONSABLE")
  @Post("pdvs/:id/resubmit")
  resubmitPdv(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.structure.decidePdv(r.actor, parse(id, i), "resubmit");
  }

  // People
  @Roles("RESPONSABLE")
  @Post("pdvs/:id/members")
  addMember(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.users.addMember(r.actor, parse(id, i), parse(Member, b));
  }
  @Roles("ADMIN")
  @Post("users")
  createUser(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.users.createByAdmin(r.actor, parse(AdminUser, b));
  }
  @Roles("ADMIN", "RESPONSABLE")
  @Get("users")
  list(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.users.list(
      r.actor,
      parse(
        z.object({
          role: z
            .enum(["ADMIN", "RESPONSABLE", "GROSSISTE", "VENDEUR"])
            .optional(),
          status: Status.optional(),
          regionId: id.optional(),
          pdvId: id.optional(),
          q: z.string().max(80).optional(),
        }),
        q,
      ),
    );
  }
  @Roles("ADMIN", "RESPONSABLE")
  @Get("users/:id")
  user(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.users.get(r.actor, parse(id, i));
  }
  @Roles("ADMIN", "RESPONSABLE")
  @Patch("users/:id")
  updateUser(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.users.update(r.actor, parse(id, i), parse(UserPatch, b));
  }
  @Roles("ADMIN")
  @Post("users/:id/approve")
  approveUser(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.users.decide(
      r.actor,
      parse(id, i),
      "approve",
      parse(Note, b ?? {}).note,
    );
  }
  @Roles("ADMIN")
  @Post("users/:id/reject")
  rejectUser(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.users.decide(
      r.actor,
      parse(id, i),
      "reject",
      parse(Note, b ?? {}).note,
    );
  }
  @Roles("ADMIN", "RESPONSABLE")
  @Post("users/:id/suspend")
  suspendUser(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.users.decide(
      r.actor,
      parse(id, i),
      "suspend",
      parse(Note, b ?? {}).note,
    );
  }
  @Roles("ADMIN")
  @Post("users/:id/reactivate")
  reactivateUser(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.users.decide(r.actor, parse(id, i), "reactivate");
  }
  @Roles("ADMIN", "RESPONSABLE")
  @Post("users/:id/resend-invite")
  resend(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.users.resendInvite(r.actor, parse(id, i));
  }

  // Depots
  @Roles("ADMIN", "RESPONSABLE", "GROSSISTE")
  @Get("depots")
  depots(@Req() r: AuthRequest) {
    return this.users.listDepots(r.actor);
  }
  @Roles("ADMIN", "GROSSISTE")
  @Patch("depots/:id")
  updateDepot(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.users.updateDepot(r.actor, parse(id, i), parse(DepotPatch, b));
  }
}
