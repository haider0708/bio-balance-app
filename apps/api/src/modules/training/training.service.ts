import { Injectable } from "@nestjs/common";
import type { LessonKind, Prisma, Role } from "@prisma/client";
import type { Actor } from "../../core/actor";
import { audit } from "../../core/audit";
import { Database, json, type Tx } from "../../core/database";
import { notFound, requireRule } from "../../core/errors";

export interface CourseAudience {
  roles?: Role[];
  regionIds?: string[];
}
export interface CourseInput {
  title: string;
  summary?: string;
  coverId?: string | null;
  audience?: CourseAudience;
}
export interface LessonInput {
  title: string;
  kind: LessonKind;
  body?: string;
  mediaId?: string | null;
  videoUrl?: string | null;
  minutes?: number | null;
}

/** Does a course reach this person? Empty selectors mean "everyone". */
function reaches(
  audience: CourseAudience,
  person: { role: Role; regionId: string | null },
) {
  const roleOk =
    !audience.roles?.length || audience.roles.includes(person.role);
  const regionOk =
    !audience.regionIds?.length ||
    (person.regionId !== null && audience.regionIds.includes(person.regionId));
  return roleOk && regionOk;
}

@Injectable()
export class TrainingService {
  constructor(private readonly db: Database) {}

  // ───────────────────────── Learning (everyone) ─────────────────────────

  /** Published courses for this person, with how far they got. Admin sees drafts too. */
  async list(actor: Actor) {
    const courses = await this.db.course.findMany({
      where: actor.role === "ADMIN" ? {} : { status: "PUBLISHED" },
      include: { lessons: { select: { id: true, minutes: true } } },
      orderBy: [{ position: "asc" }, { createdAt: "asc" }],
    });
    const visible = courses.filter(
      (c) =>
        actor.role === "ADMIN" || reaches(c.audience as CourseAudience, actor),
    );
    const done = await this.db.lessonProgress.findMany({
      where: {
        userId: actor.id,
        lessonId: { in: visible.flatMap((c) => c.lessons.map((l) => l.id)) },
      },
      select: { lessonId: true },
    });
    const completed = new Set(done.map((d) => d.lessonId));
    return visible.map((c) => {
      const finished = c.lessons.filter((l) => completed.has(l.id)).length;
      return {
        id: c.id,
        title: c.title,
        summary: c.summary,
        coverId: c.coverId,
        status: c.status,
        audience: c.audience,
        lessonCount: c.lessons.length,
        completedCount: finished,
        minutes: c.lessons.reduce((sum, l) => sum + (l.minutes ?? 0), 0),
        done: c.lessons.length > 0 && finished === c.lessons.length,
      };
    });
  }

  async get(actor: Actor, id: string) {
    const course = await this.db.course.findUnique({
      where: { id },
      include: { lessons: { orderBy: { position: "asc" } } },
    });
    const allowed =
      course &&
      (actor.role === "ADMIN" ||
        (course.status === "PUBLISHED" &&
          reaches(course.audience as CourseAudience, actor)));
    if (!course || !allowed) throw notFound("Course");
    const done = await this.db.lessonProgress.findMany({
      where: {
        userId: actor.id,
        lessonId: { in: course.lessons.map((l) => l.id) },
      },
    });
    const completed = new Map(done.map((d) => [d.lessonId, d.completedAt]));
    return {
      id: course.id,
      title: course.title,
      summary: course.summary,
      coverId: course.coverId,
      status: course.status,
      audience: course.audience,
      lessons: course.lessons.map((l) => ({
        id: l.id,
        position: l.position,
        title: l.title,
        kind: l.kind,
        body: l.body,
        mediaId: l.mediaId,
        videoUrl: l.videoUrl,
        minutes: l.minutes,
        completedAt: completed.get(l.id) ?? null,
      })),
    };
  }

  async complete(actor: Actor, lessonId: string, done: boolean) {
    const lesson = await this.db.lesson.findUnique({
      where: { id: lessonId },
      include: { course: true },
    });
    const allowed =
      lesson &&
      lesson.course.status === "PUBLISHED" &&
      reaches(lesson.course.audience as CourseAudience, actor);
    if (!lesson || !allowed) throw notFound("Lesson");
    if (done)
      await this.db.lessonProgress.upsert({
        where: { userId_lessonId: { userId: actor.id, lessonId } },
        create: { userId: actor.id, lessonId },
        update: {},
      });
    else
      await this.db.lessonProgress.deleteMany({
        where: { userId: actor.id, lessonId },
      });
    return { ok: true };
  }

  // ───────────────────────── Authoring (admin) ─────────────────────────

  createCourse(actor: Actor, input: CourseInput) {
    return this.db.run(actor, async (tx) => {
      await this.checkCover(tx, input.coverId);
      const last = await tx.course.aggregate({ _max: { position: true } });
      const course = await tx.course.create({
        data: {
          title: input.title,
          summary: input.summary ?? "",
          coverId: input.coverId ?? null,
          audience: json(input.audience ?? {}),
          position: (last._max.position ?? 0) + 1,
          createdById: actor.id,
        },
      });
      await audit(tx, actor, "course.created", "Course", course.id, {
        title: course.title,
      });
      return course;
    });
  }

  updateCourse(actor: Actor, id: string, input: Partial<CourseInput>) {
    return this.db.run(actor, async (tx) => {
      await this.checkCover(tx, input.coverId);
      const course = await tx.course.findUnique({ where: { id } });
      if (!course) throw notFound("Course");
      const updated = await tx.course.update({
        where: { id },
        data: {
          ...(input.title !== undefined && { title: input.title }),
          ...(input.summary !== undefined && { summary: input.summary }),
          ...(input.coverId !== undefined && { coverId: input.coverId }),
          ...(input.audience !== undefined && {
            audience: json(input.audience),
          }),
        },
      });
      await audit(tx, actor, "course.updated", "Course", id, {
        fields: Object.keys(input),
      });
      return updated;
    });
  }

  /** Publish when it has at least one lesson; unpublish to edit freely. */
  setPublished(actor: Actor, id: string, published: boolean) {
    return this.db.run(actor, async (tx) => {
      const course = await tx.course.findUnique({
        where: { id },
        include: { lessons: { select: { id: true } } },
      });
      if (!course) throw notFound("Course");
      requireRule(
        !published || course.lessons.length > 0,
        "EMPTY_COURSE",
        "Add at least one lesson before publishing.",
      );
      const updated = await tx.course.update({
        where: { id },
        data: {
          status: published ? "PUBLISHED" : "DRAFT",
          publishedAt: published ? new Date() : null,
        },
      });
      await audit(
        tx,
        actor,
        published ? "course.published" : "course.unpublished",
        "Course",
        id,
        {},
      );
      return updated;
    });
  }

  deleteCourse(actor: Actor, id: string) {
    return this.db.run(actor, async (tx) => {
      const course = await tx.course.findUnique({ where: { id } });
      if (!course) throw notFound("Course");
      await tx.course.delete({ where: { id } });
      await audit(tx, actor, "course.deleted", "Course", id, {
        title: course.title,
      });
      return { ok: true };
    });
  }

  addLesson(actor: Actor, courseId: string, input: LessonInput) {
    return this.db.run(actor, async (tx) => {
      const course = await tx.course.findUnique({ where: { id: courseId } });
      if (!course) throw notFound("Course");
      await this.checkLesson(tx, input);
      const last = await tx.lesson.aggregate({
        where: { courseId },
        _max: { position: true },
      });
      const lesson = await tx.lesson.create({
        data: {
          courseId,
          position: (last._max.position ?? 0) + 1,
          ...this.lessonData(input),
        } as Prisma.LessonUncheckedCreateInput,
      });
      await audit(tx, actor, "lesson.created", "Lesson", lesson.id, {
        courseId,
      });
      return lesson;
    });
  }

  updateLesson(actor: Actor, id: string, input: Partial<LessonInput>) {
    return this.db.run(actor, async (tx) => {
      const lesson = await tx.lesson.findUnique({ where: { id } });
      if (!lesson) throw notFound("Lesson");
      const merged = {
        title: lesson.title,
        kind: lesson.kind,
        body: lesson.body,
        mediaId: lesson.mediaId,
        videoUrl: lesson.videoUrl,
        ...input,
      };
      await this.checkLesson(tx, merged);
      const updated = await tx.lesson.update({
        where: { id },
        data: this.lessonData(input),
      });
      await audit(tx, actor, "lesson.updated", "Lesson", id, {
        fields: Object.keys(input),
      });
      return updated;
    });
  }

  deleteLesson(actor: Actor, id: string) {
    return this.db.run(actor, async (tx) => {
      const lesson = await tx.lesson.findUnique({
        where: { id },
        include: { course: { include: { lessons: { select: { id: true } } } } },
      });
      if (!lesson) throw notFound("Lesson");
      requireRule(
        lesson.course.status === "DRAFT" || lesson.course.lessons.length > 1,
        "EMPTY_COURSE",
        "Unpublish the course before removing its last lesson.",
        409,
      );
      await tx.lesson.delete({ where: { id } });
      return { ok: true };
    });
  }

  reorderLessons(actor: Actor, courseId: string, ids: string[]) {
    return this.db.run(actor, async (tx) => {
      const lessons = await tx.lesson.findMany({
        where: { courseId },
        select: { id: true },
      });
      requireRule(
        lessons.length === ids.length &&
          lessons.every((l) => ids.includes(l.id)),
        "ORDER_INVALID",
        "The order must list every lesson once.",
      );
      for (const [index, id] of ids.entries())
        await tx.lesson.update({
          where: { id },
          data: { position: index + 1 },
        });
      return { ok: true };
    });
  }

  reorderCourses(actor: Actor, ids: string[]) {
    return this.db.run(actor, async (tx) => {
      const courses = await tx.course.findMany({ select: { id: true } });
      requireRule(
        courses.length === ids.length &&
          courses.every((c) => ids.includes(c.id)),
        "ORDER_INVALID",
        "The order must list every course once.",
      );
      for (const [index, id] of ids.entries())
        await tx.course.update({
          where: { id },
          data: { position: index + 1 },
        });
      return { ok: true };
    });
  }

  /** Who finished what: every person the course is for, with their progress. */
  async progress(id: string) {
    const course = await this.db.course.findUnique({
      where: { id },
      include: { lessons: { select: { id: true } } },
    });
    if (!course) throw notFound("Course");
    const audience = course.audience as CourseAudience;
    const people = await this.db.user.findMany({
      where: {
        status: "ACTIVE",
        role: { not: "ADMIN" },
        ...(audience.roles?.length && { role: { in: audience.roles } }),
        ...(audience.regionIds?.length && {
          regionId: { in: audience.regionIds },
        }),
      },
      select: { id: true, name: true, role: true, regionId: true },
      orderBy: { name: "asc" },
    });
    const done = await this.db.lessonProgress.groupBy({
      by: ["userId"],
      where: { lessonId: { in: course.lessons.map((l) => l.id) } },
      _count: { _all: true },
    });
    const count = new Map(done.map((d) => [d.userId, d._count._all]));
    const total = course.lessons.length;
    const rows = people.map((p) => ({
      userId: p.id,
      name: p.name,
      role: p.role,
      regionId: p.regionId,
      completed: count.get(p.id) ?? 0,
      total,
    }));
    return {
      total,
      people: rows.length,
      finished: rows.filter((r) => total > 0 && r.completed === total).length,
      rows,
    };
  }

  // ───────────────────────── Helpers ─────────────────────────

  private async checkCover(tx: Tx, mediaId?: string | null) {
    if (!mediaId) return;
    const media = await tx.mediaAsset.findUnique({ where: { id: mediaId } });
    requireRule(
      media?.purpose === "TRAINING" && media.mime.startsWith("image/"),
      "MEDIA_SCOPE",
      "Use an uploaded training image.",
    );
  }

  private async checkLesson(
    tx: Tx,
    input: {
      kind: LessonKind;
      body?: string | null;
      mediaId?: string | null;
      videoUrl?: string | null;
    },
  ) {
    if (input.kind === "ARTICLE")
      requireRule(
        input.body?.trim(),
        "BODY_REQUIRED",
        "Write the lesson text.",
      );
    if (input.kind === "VIDEO") {
      requireRule(
        input.mediaId || input.videoUrl,
        "VIDEO_REQUIRED",
        "Add a video file or a link.",
      );
      requireRule(
        !input.videoUrl || /^https:\/\//.test(input.videoUrl),
        "VIDEO_URL",
        "The video link must start with https://.",
      );
    }
    if (input.mediaId) {
      const media = await tx.mediaAsset.findUnique({
        where: { id: input.mediaId },
      });
      requireRule(
        media?.purpose === "TRAINING",
        "MEDIA_SCOPE",
        "Use an uploaded training file.",
      );
      requireRule(
        input.kind !== "PDF" || media.mime === "application/pdf",
        "MEDIA_SCOPE",
        "A document lesson needs a PDF.",
      );
      requireRule(
        input.kind !== "VIDEO" || media.mime === "video/mp4",
        "MEDIA_SCOPE",
        "A video lesson needs an MP4 file.",
      );
    }
    if (input.kind === "PDF")
      requireRule(input.mediaId, "PDF_REQUIRED", "Upload the PDF.");
  }

  private lessonData(input: Partial<LessonInput>) {
    return {
      ...(input.title !== undefined && { title: input.title }),
      ...(input.kind !== undefined && { kind: input.kind }),
      ...(input.body !== undefined && { body: input.body }),
      ...(input.mediaId !== undefined && { mediaId: input.mediaId }),
      ...(input.videoUrl !== undefined && { videoUrl: input.videoUrl }),
      ...(input.minutes !== undefined && { minutes: input.minutes }),
    };
  }
}
