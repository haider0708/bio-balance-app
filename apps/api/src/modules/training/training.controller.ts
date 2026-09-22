import { TrainingRequests } from "../../shared/contracts/requests";
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
    return this.service.save(r.actor, TrainingRequests.Save.parse(b));
  }
  @Get("training/:id") get(@Req() r: AuthRequest, @Param("id") id: string) {
    return this.service.get(r.actor, z.uuid().parse(id));
  }
  @Post("media/uploads") start(@Req() r: AuthRequest, @Body() b: unknown) {
    const v = TrainingRequests.Start.parse(b);
    return this.service.startUpload(r.actor, v.fileName, v.mime, v.size, v);
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
  @Get("media/:id/metadata") metadata(
    @Req() r: AuthRequest,
    @Param("id") id: string,
  ) {
    return this.service.metadata(r.actor, z.uuid().parse(id));
  }
  @Get("media/:id") async media(
    @Req() r: AuthRequest,
    @Param("id") id: string,
    @Res() response: Response,
  ) {
    const file = await this.service.media(r.actor, z.uuid().parse(id));
    response.setHeader("Cache-Control", "private, no-store");
    if (file.sha256) {
      response.setHeader("X-Content-SHA256", file.sha256);
      response.setHeader("ETag", `"${file.sha256}"`);
    }
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
