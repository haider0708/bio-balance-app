import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Put,
  Req,
} from "@nestjs/common";
import { z } from "zod";
import { type AuthRequest, Roles, parse } from "../../core/http";
import { TrainingService } from "./training.service";

const id = z.uuid();
const Audience = z.object({
  roles: z
    .array(z.enum(["RESPONSABLE", "GROSSISTE", "VENDEUR"]))
    .max(3)
    .optional(),
  regionIds: z.array(id).max(3).optional(),
});
const Course = z.object({
  title: z.string().trim().min(2).max(140),
  summary: z.string().trim().max(500).optional(),
  coverId: id.nullable().optional(),
  audience: Audience.optional(),
});
const Lesson = z.object({
  title: z.string().trim().min(2).max(140),
  kind: z.enum(["ARTICLE", "VIDEO", "PDF"]),
  body: z.string().max(20_000).optional(),
  mediaId: id.nullable().optional(),
  videoUrl: z.string().trim().max(500).nullable().optional(),
  minutes: z.number().int().min(1).max(600).nullable().optional(),
});
const Order = z.object({ ids: z.array(id).min(1).max(200) });

@Controller("v1")
export class TrainingController {
  constructor(private readonly training: TrainingService) {}

  @Get("courses") list(@Req() r: AuthRequest) {
    return this.training.list(r.actor);
  }
  @Get("courses/:id") get(@Req() r: AuthRequest, @Param("id") i: string) {
    return this.training.get(r.actor, parse(id, i));
  }
  @Post("lessons/:id/complete") complete(
    @Req() r: AuthRequest,
    @Param("id") i: string,
  ) {
    return this.training.complete(r.actor, parse(id, i), true);
  }
  @Delete("lessons/:id/complete") undo(
    @Req() r: AuthRequest,
    @Param("id") i: string,
  ) {
    return this.training.complete(r.actor, parse(id, i), false);
  }

  @Roles("ADMIN") @Post("courses") create(
    @Req() r: AuthRequest,
    @Body() b: unknown,
  ) {
    return this.training.createCourse(r.actor, parse(Course, b));
  }
  @Roles("ADMIN") @Put("courses/order") reorder(
    @Req() r: AuthRequest,
    @Body() b: unknown,
  ) {
    return this.training.reorderCourses(r.actor, parse(Order, b).ids);
  }
  @Roles("ADMIN") @Patch("courses/:id") update(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.training.updateCourse(
      r.actor,
      parse(id, i),
      parse(Course.partial(), b),
    );
  }
  @Roles("ADMIN") @Post("courses/:id/publish") publish(
    @Req() r: AuthRequest,
    @Param("id") i: string,
  ) {
    return this.training.setPublished(r.actor, parse(id, i), true);
  }
  @Roles("ADMIN") @Post("courses/:id/unpublish") unpublish(
    @Req() r: AuthRequest,
    @Param("id") i: string,
  ) {
    return this.training.setPublished(r.actor, parse(id, i), false);
  }
  @Roles("ADMIN") @Delete("courses/:id") remove(
    @Req() r: AuthRequest,
    @Param("id") i: string,
  ) {
    return this.training.deleteCourse(r.actor, parse(id, i));
  }
  @Roles("ADMIN") @Get("courses/:id/progress") progress(
    @Param("id") i: string,
  ) {
    return this.training.progress(parse(id, i));
  }
  @Roles("ADMIN") @Post("courses/:id/lessons") addLesson(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.training.addLesson(r.actor, parse(id, i), parse(Lesson, b));
  }
  @Roles("ADMIN") @Put("courses/:id/lessons/order") reorderLessons(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.training.reorderLessons(
      r.actor,
      parse(id, i),
      parse(Order, b).ids,
    );
  }
  @Roles("ADMIN") @Patch("lessons/:id") updateLesson(
    @Req() r: AuthRequest,
    @Param("id") i: string,
    @Body() b: unknown,
  ) {
    return this.training.updateLesson(
      r.actor,
      parse(id, i),
      parse(Lesson.partial(), b),
    );
  }
  @Roles("ADMIN") @Delete("lessons/:id") removeLesson(
    @Req() r: AuthRequest,
    @Param("id") i: string,
  ) {
    return this.training.deleteLesson(r.actor, parse(id, i));
  }
}
