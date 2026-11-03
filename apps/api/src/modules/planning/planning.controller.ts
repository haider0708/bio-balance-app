import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Put,
  Query,
  Req,
} from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { PlanningService } from "./planning.service";

const id = z.uuid();
const day = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);
const Kind = z.enum(["COUNT", "DELIVERY", "TRAINING", "FOLLOW_UP", "OTHER"]);
const Place = z.enum(["PDV", "DEPOT"]);

const Presence = z
  .object({
    occurredAt: z.coerce.date().optional(),
    latitude: z.number().min(-90).max(90).optional(),
    longitude: z.number().min(-180).max(180).optional(),
    accuracyMeters: z.number().min(0).max(100_000).optional(),
    mocked: z.boolean().optional(),
    reason: z.string().trim().max(300).optional(),
  })
  .refine((p) => (p.latitude === undefined) === (p.longitude === undefined), {
    message: "Give both latitude and longitude, or neither.",
  });

const Create = z.object({
  targetKind: Place,
  targetId: id,
  kind: Kind,
  start: z.coerce.date(),
  durationMinutes: z.number().int().min(15).max(480).default(60),
  note: z.string().trim().max(500).optional(),
  allowOverlap: z.boolean().optional(),
});
const Update = z.object({
  targetKind: Place.optional(),
  targetId: id.optional(),
  kind: Kind.optional(),
  start: z.coerce.date().optional(),
  durationMinutes: z.number().int().min(15).max(480).optional(),
  note: z.string().trim().max(500).optional(),
  allowOverlap: z.boolean().optional(),
});
const Position = z.object({
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  accuracyMeters: z.number().min(0).max(100_000).optional(),
  locked: z.boolean().optional(),
});

@Controller("v1")
export class PlanningController {
  constructor(private readonly planning: PlanningService) {}

  // Visits (responsable plans; the admin only reads)
  @Roles("RESPONSABLE", "ADMIN")
  @Get("visits")
  list(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.planning.list(
      r.actor,
      parse(
        z.object({
          from: day,
          to: day,
          responsableId: id.optional(),
          regionId: id.optional(),
          status: z
            .enum(["PLANNED", "ON_SITE", "DONE", "MISSED", "CANCELLED"])
            .optional(),
        }),
        q,
      ),
    );
  }
  @Roles("RESPONSABLE")
  @Post("visits")
  create(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.planning.create(r.actor, parse(Create, b));
  }
  // Before ":id", so "unplanned" is not read as an id.
  @Roles("RESPONSABLE")
  @Post("visits/unplanned")
  unplanned(@Req() r: AuthRequest, @Body() b: unknown) {
    const body = parse(
      z.intersection(
        z.object({ id, targetKind: Place, targetId: id, kind: Kind }),
        Presence,
      ),
      b,
    );
    return this.planning.startUnplanned(r.actor, body);
  }
  @Roles("RESPONSABLE", "ADMIN")
  @Get("visits/:id")
  get(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.planning.get(r.actor, parse(id, i));
  }
  @Roles("RESPONSABLE")
  @Patch("visits/:id")
  update(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.planning.update(r.actor, parse(id, i), parse(Update, b));
  }
  @Roles("RESPONSABLE")
  @Post("visits/:id/cancel")
  cancel(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.planning.cancel(r.actor, parse(id, i));
  }
  @Roles("RESPONSABLE")
  @Post("visits/:id/check-in")
  checkIn(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.planning.checkIn(
      r.actor,
      parse(id, i),
      parse(Presence, b ?? {}),
    );
  }
  @Roles("RESPONSABLE")
  @Post("visits/:id/check-out")
  checkOut(@Req() r: AuthRequest, @Param("id") i: string, @Body() b: unknown) {
    return this.planning.checkOut(
      r.actor,
      parse(id, i),
      parse(Presence, b ?? {}),
    );
  }

  // Where each place is
  @Roles("RESPONSABLE", "ADMIN")
  @Put("planning/positions/:kind/:id")
  position(
    @Req() r: AuthRequest,
    @Param("kind") k: string,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.planning.setPosition(
      r.actor,
      parse(Place, k.toUpperCase()),
      parse(id, i),
      parse(Position, b),
    );
  }

  // Preferences and the calendar link
  @Roles("RESPONSABLE")
  @Get("planning/preferences")
  preferences(@Req() r: AuthRequest) {
    return this.planning.preferences(r.actor);
  }
  @Roles("RESPONSABLE")
  @Put("planning/preferences")
  setPreferences(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.planning.setPreferences(
      r.actor,
      parse(
        z.object({
          leadMinutes: z.number().int().optional(),
          eveningSummary: z.boolean().optional(),
        }),
        b,
      ),
    );
  }
  @Roles("RESPONSABLE")
  @Get("planning/calendar-link")
  link(@Req() r: AuthRequest) {
    return this.planning.calendarLink(r.actor);
  }
  @Roles("RESPONSABLE")
  @Post("planning/calendar-link/rotate")
  rotate(@Req() r: AuthRequest) {
    return this.planning.calendarLink(r.actor, true);
  }

  // The admin's overview
  @Roles("ADMIN")
  @Get("planning/overview")
  overview(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.planning.overview(
      r.actor,
      parse(z.object({ from: day, to: day, regionId: id.optional() }), q),
    );
  }
}
