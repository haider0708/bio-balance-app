import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Query,
  Req,
} from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { PageQuery } from "../../core/pagination";
import { MessagingService } from "./messaging.service";

const id = z.uuid();
const Audience = z.object({
  all: z.boolean().optional(),
  roles: z
    .array(z.enum(["RESPONSABLE", "VENDEUR"]))
    .max(3)
    .optional(),
  regionIds: z.array(id).max(3).optional(),
  pdvIds: z.array(id).max(500).optional(),
  userIds: z.array(id).max(1000).optional(),
});
const Message = z.object({
  title: z.string().trim().min(2).max(120),
  body: z.string().trim().min(2).max(4000),
  audience: Audience,
  pinned: z.boolean().optional(),
  scheduledFor: z.coerce.date().nullable().optional(),
});

@Controller("v1")
export class MessagingController {
  constructor(private readonly messaging: MessagingService) {}

  @Get("notifications")
  inbox(@Req() r: AuthRequest, @Query() q: Record<string, string>) {
    return this.messaging.inbox(
      r.actor,
      parse(
        PageQuery.extend({
          unreadOnly: z.stringbool().optional(),
          category: z
            .enum([
              "SALES",
              "STOCK",
              "RESTOCKS",
              "PAYMENTS",
              "NETWORK",
              "MESSAGES",
            ])
            .optional(),
        }),
        q,
      ),
    );
  }
  @Get("notifications/unread-count")
  unread(@Req() r: AuthRequest) {
    return this.messaging.unreadCount(r.actor);
  }
  @Post("notifications/read-all")
  readAll(@Req() r: AuthRequest) {
    return this.messaging.markAllRead(r.actor);
  }
  @Post("notifications/:id/read")
  read(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.messaging.markRead(r.actor, parse(id, i));
  }

  @Roles("ADMIN")
  @Post("messages/preview")
  preview(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.messaging.preview(
      r.actor,
      parse(z.object({ audience: Audience }), b).audience,
    );
  }
  @Roles("ADMIN")
  @Post("messages")
  send(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.messaging.send(r.actor, parse(Message, b));
  }
  @Roles("ADMIN")
  @Get("messages")
  list(@Req() r: AuthRequest) {
    return this.messaging.list(r.actor);
  }
  @Roles("ADMIN")
  @Get("messages/:id/recipients")
  recipients(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.messaging.recipients(r.actor, parse(id, i));
  }
  @Roles("ADMIN")
  @Delete("messages/:id")
  cancel(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.messaging.cancelScheduled(r.actor, parse(id, i));
  }
}
