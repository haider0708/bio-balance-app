import {
  Body,
  Controller,
  Get,
  Headers,
  Param,
  Post,
  Put,
  Query,
  Req,
  Res,
} from "@nestjs/common";
import { ApiTags, ApiBearerAuth } from "@nestjs/swagger";
import { z } from "zod";
import { Response } from "express";
import { AuthRequest } from "../../shared/infrastructure/http";
import { TrainingService } from "./training.service";
import { requireRule } from "../../shared/domain/errors";
@ApiTags("training")
@ApiBearerAuth()
@Controller("v1")
export class TrainingController {
  constructor(private readonly service: TrainingService) {}
  @Get("training") list(@Req() r: AuthRequest, @Query("after") after?: string) {
    return this.service.list(r.actor, z.uuid().optional().parse(after));
  }
  @Post("training") save(@Req() r: AuthRequest, @Body() b: unknown) {
    return this.service.save(
      r.actor,
      z
        .object({
          id: z.uuid().optional(),
          title: z.string().trim().min(3).max(200),
          body: z.string().max(100_000),
          type: z.enum(["article", "video"]),
          mediaId: z.uuid().optional(),
          productIds: z.array(z.uuid()).max(100).default([]),
          status: z.enum(["draft", "published", "archived"]),
          expectedVersion: z.number().int().positive().optional(),
        })
        .strict()
        .parse(b),
    );
  }
  @Post("media/uploads") start(@Req() r: AuthRequest, @Body() b: unknown) {
    const v = z
      .object({
        fileName: z.string().min(1).max(200),
        mime: z.enum([
          "image/jpeg",
          "image/png",
          "video/mp4",
          "video/quicktime",
        ]),
        size: z
          .number()
          .int()
          .positive()
          .max(500 * 1024 * 1024),
      })
      .strict()
      .parse(b);
    return this.service.startUpload(r.actor, v.fileName, v.mime, v.size);
  }
  @Get("media/uploads/:id") status(
    @Req() r: AuthRequest,
    @Param("id") id: string,
  ) {
    return this.service.uploadStatus(r.actor, z.uuid().parse(id));
  }
  @Put("media/uploads/:id") chunk(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Headers("upload-offset") offset: string,
    @Body() body: unknown,
  ) {
    requireRule(
      Buffer.isBuffer(body),
      "INVALID_CONTENT_TYPE",
      "Format de fragment invalide.",
    );
    return this.service.chunk(
      r.actor,
      z.uuid().parse(id),
      z.coerce
        .number()
        .int()
        .min(0)
        .max(500 * 1024 * 1024)
        .parse(offset),
      body,
    );
  }
  @Get("media/:id") async media(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Res() response: Response,
  ) {
    const file = await this.service.media(r.actor, z.uuid().parse(id));
    response.setHeader("Cache-Control", "private, max-age=3600");
    if (process.env.MEDIA_INTERNAL_REDIRECT === "true") {
      response
        .type(file.mime)
        .setHeader(
          "X-Accel-Redirect",
          `/_media/${file.path.split("/").at(-1)}`,
        );
      response.end();
    } else
      response
        .type(file.mime)
        .sendFile(file.path, { acceptRanges: true, dotfiles: "deny" });
  }
}
