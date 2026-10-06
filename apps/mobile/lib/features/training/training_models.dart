import '../../core/api/json.dart';

class Course {
  const Course({
    required this.id,
    required this.title,
    required this.summary,
    required this.published,
    required this.lessonCount,
    required this.completedCount,
    required this.minutes,
    required this.audienceRoles,
    required this.audienceRegions,
    this.coverId,
  });

  factory Course.fromJson(Json j) => Course(
    id: j.str('id'),
    title: j.str('title'),
    summary: j.str('summary'),
    coverId: j.strOrNull('coverId'),
    published: j.str('status') == 'PUBLISHED',
    lessonCount: j.integer('lessonCount'),
    completedCount: j.integer('completedCount'),
    minutes: j.integer('minutes'),
    audienceRoles: ((j.obj('audience')['roles'] as List<dynamic>?) ?? const [])
        .cast<String>(),
    audienceRegions:
        ((j.obj('audience')['regionIds'] as List<dynamic>?) ?? const [])
            .cast<String>(),
  );

  final String id;
  final String title;
  final String summary;
  final String? coverId;
  final bool published;
  final int lessonCount;
  final int completedCount;
  final int minutes;
  final List<String> audienceRoles;
  final List<String> audienceRegions;

  bool get done => lessonCount > 0 && completedCount >= lessonCount;
  double get progress => lessonCount == 0 ? 0 : completedCount / lessonCount;
}

enum LessonKind {
  article,
  video,
  pdf;

  static LessonKind parse(String v) => LessonKind.values.firstWhere(
    (k) => k.name.toUpperCase() == v,
    orElse: () => LessonKind.article,
  );
  String get wire => name.toUpperCase();
}

class Lesson {
  const Lesson({
    required this.id,
    required this.position,
    required this.title,
    required this.kind,
    required this.body,
    this.mediaId,
    this.videoUrl,
    this.minutes,
    this.completedAt,
  });

  factory Lesson.fromJson(Json j) => Lesson(
    id: j.str('id'),
    position: j.integer('position'),
    title: j.str('title'),
    kind: LessonKind.parse(j.str('kind')),
    body: j.str('body'),
    mediaId: j.strOrNull('mediaId'),
    videoUrl: j.strOrNull('videoUrl'),
    minutes: j.integerOrNull('minutes'),
    completedAt: j.dateOrNull('completedAt'),
  );

  final String id;
  final int position;
  final String title;
  final LessonKind kind;
  final String body;
  final String? mediaId;
  final String? videoUrl;
  final int? minutes;
  final DateTime? completedAt;

  bool get done => completedAt != null;
}

class CourseDetail {
  const CourseDetail({required this.course, required this.lessons});

  factory CourseDetail.fromJson(Json j) {
    final lessons = j.list('lessons').map(Lesson.fromJson).toList();
    return CourseDetail(
      lessons: lessons,
      course: Course(
        id: j.str('id'),
        title: j.str('title'),
        summary: j.str('summary'),
        coverId: j.strOrNull('coverId'),
        published: j.str('status') == 'PUBLISHED',
        lessonCount: lessons.length,
        completedCount: lessons.where((l) => l.done).length,
        minutes: lessons.fold(0, (s, l) => s + (l.minutes ?? 0)),
        audienceRoles:
            ((j.obj('audience')['roles'] as List<dynamic>?) ?? const [])
                .cast<String>(),
        audienceRegions:
            ((j.obj('audience')['regionIds'] as List<dynamic>?) ?? const [])
                .cast<String>(),
      ),
    );
  }

  final Course course;
  final List<Lesson> lessons;
}

class CourseProgressRow {
  const CourseProgressRow({
    required this.userId,
    required this.name,
    required this.role,
    required this.completed,
    required this.total,
  });

  factory CourseProgressRow.fromJson(Json j) => CourseProgressRow(
    userId: j.str('userId'),
    name: j.str('name'),
    role: j.str('role'),
    completed: j.integer('completed'),
    total: j.integer('total'),
  );

  final String userId;
  final String name;
  final String role;
  final int completed;
  final int total;
}

class CourseProgress {
  const CourseProgress({
    required this.total,
    required this.people,
    required this.finished,
    required this.rows,
  });

  factory CourseProgress.fromJson(Json j) => CourseProgress(
    total: j.integer('total'),
    people: j.integer('people'),
    finished: j.integer('finished'),
    rows: j.list('rows').map(CourseProgressRow.fromJson).toList(),
  );

  final int total;
  final int people;
  final int finished;
  final List<CourseProgressRow> rows;
}
