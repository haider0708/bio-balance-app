import { Controller, Get, Param, Post, Query, Req, Res } from "@nestjs/common";
import type { Response } from "express";
import { z } from "zod";
import { type AuthRequest, parse } from "../../core/http";
import { MediaService } from "./media.service";

const Upload = z.object({
  purpose: z.enum(["PROOF", "PRODUCT", "TRAINING"]),
  filename: z.string().max(200).default("file"),
});

/** The body is streamed straight to disk; main.ts leaves this route's body unparsed. */
@Controller("v1/media")
export class MediaController {
  constructor(private readonly media: MediaService) {}

  @Post()
  upload(@Req() req: AuthRequest, @Query() q: Record<string, string>) {
    const v = parse(Upload, q);
    return this.media.upload(req.actor, v.purpose, v.filename, req);
  }

  @Get(":id")
  async get(@Req() req: AuthRequest, @Param("id") id: string, @Res() res: Response) {
    const file = await this.media.open(req.actor, parse(z.uuid(), id));
    res.setHeader("Cache-Control", "private, max-age=3600");
    res.setHeader("ETag", `"${file.sha256}"`);
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.type(file.mime).sendFile(file.file, { acceptRanges: true, dotfiles: "deny" });
  }
}
