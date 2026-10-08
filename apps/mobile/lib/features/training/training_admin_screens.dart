import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../media/media_repository.dart';
import '../network/network_repository.dart';
import 'training_models.dart';
import 'training_repository.dart';
import 'training_screens.dart';

/// The admin's list of courses, drafts included.
class ManageCoursesScreen extends ConsumerWidget {
  const ManageCoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final courses = ref.watch(coursesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.manageTraining)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () async {
          final title = await _askTitle(context);
          if (title == null || !context.mounted) return;
          Course? created;
          if (await perform(
            context,
            () async => created = await ref
                .read(trainingRepositoryProvider)
                .createCourse({'title': title}),
          )) {
            ref.invalidate(coursesProvider);
            if (context.mounted)
              await context.push('/training/manage/${created!.id}');
            ref.invalidate(coursesProvider);
          }
        },
        icon: const Icon(LucideIcons.plus),
        label: Text(t.newCourse),
      ),
      body: AsyncBody(
        value: courses,
        onRetry: () => ref.invalidate(coursesProvider),
        isEmpty: (l) => l.isEmpty,
        empty: EmptyState(
          icon: LucideIcons.graduationCap,
          title: t.noCourses,
          message: t.noCoursesAdminHint,
        ),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Gap(12),
          itemBuilder: (context, i) => CourseCard(
            course: list[i],
            showStatus: true,
            onTap: () async {
              await context.push('/training/manage/${list[i].id}');
              ref.invalidate(coursesProvider);
            },
          ),
        ),
      ),
    );
  }

  Future<String?> _askTitle(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(t.newCourse, style: context.text.titleLarge),
            const Gap(16),
            TextField(
              controller: c,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: t.courseTitle),
            ),
            const Gap(16),
            FilledButton(
              onPressed: () => c.text.trim().length >= 2
                  ? Navigator.pop(context, c.text.trim())
                  : null,
              child: Text(t.create),
            ),
          ],
        ),
      ),
    ).whenComplete(c.dispose);
  }
}

/// Edit a course: its text, who it is for, its lessons, and publish it.
class CourseEditorScreen extends ConsumerStatefulWidget {
  const CourseEditorScreen({required this.courseId, super.key});

  final String courseId;

  @override
  ConsumerState<CourseEditorScreen> createState() => _CourseEditorScreenState();
}

class _CourseEditorScreenState extends ConsumerState<CourseEditorScreen> {
  final _title = TextEditingController();
  final _summary = TextEditingController();
  bool _loaded = false;
  Set<String> _roles = {};
  Set<String> _regions = {};

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    super.dispose();
  }

  void _reload() {
    ref.invalidate(courseProvider(widget.courseId));
    ref.invalidate(coursesProvider);
  }

  Future<void> _saveDetails() async {
    final t = AppLocalizations.of(context);
    await perform(
      context,
      () => ref.read(trainingRepositoryProvider).updateCourse(widget.courseId, {
        'title': _title.text.trim(),
        'summary': _summary.text.trim(),
        'audience': {'roles': _roles.toList(), 'regionIds': _regions.toList()},
      }),
      success: t.saved,
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final detail = ref.watch(courseProvider(widget.courseId));
    final regions = ref.watch(regionsProvider).value ?? const [];
    final repo = ref.read(trainingRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.editCourse),
        actions: [
          IconButton(
            tooltip: t.progress,
            icon: const Icon(LucideIcons.chartNoAxesColumn),
            onPressed: () =>
                context.push('/training/manage/${widget.courseId}/progress'),
          ),
        ],
      ),
      body: AsyncBody(
        value: detail,
        onRetry: _reload,
        builder: (d) {
          if (!_loaded) {
            _loaded = true;
            _title.text = d.course.title;
            _summary.text = d.course.summary;
            _roles = {...d.course.audienceRoles};
            _regions = {...d.course.audienceRegions};
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatusChip(
                      d.course.published ? t.published : t.draft,
                      tone: d.course.published ? Tone.success : Tone.muted,
                    ),
                  ),
                ],
              ),
              const Gap(12),
              TextField(
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: t.courseTitle),
              ),
              const Gap(12),
              TextField(
                controller: _summary,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: t.courseSummary),
              ),
              SectionHeader(t.whoIsItFor),
              Text(
                t.courseAudienceHint,
                style: context.text.bodySmall?.copyWith(
                  color: context.status.muted,
                ),
              ),
              const Gap(8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (value, label) in [
                    ('RESPONSABLE', t.roleResponsablePlural),
                    ('GROSSISTE', t.roleGrossistePlural),
                    ('VENDEUR', t.roleVendeurPlural),
                  ])
                    FilterChip(
                      label: Text(label),
                      selected: _roles.contains(value),
                      onSelected: (on) => setState(
                        () => on ? _roles.add(value) : _roles.remove(value),
                      ),
                    ),
                ],
              ),
              const Gap(8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in regions)
                    FilterChip(
                      label: Text(r.name),
                      selected: _regions.contains(r.id),
                      onSelected: (on) => setState(
                        () => on ? _regions.add(r.id) : _regions.remove(r.id),
                      ),
                    ),
                ],
              ),
              const Gap(12),
              OutlinedButton(onPressed: _saveDetails, child: Text(t.save)),
              SectionHeader(
                t.lessons,
                trailing: TextButton.icon(
                  onPressed: () async {
                    await context.push(
                      '/training/manage/${widget.courseId}/lessons/new',
                    );
                    _reload();
                  },
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: Text(t.addLesson),
                ),
              ),
              if (d.lessons.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    t.noLessonsYet,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                ),
              ReorderableListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                onReorderItem: (from, to) async {
                  final ids = d.lessons.map((l) => l.id).toList();
                  ids.insert(to, ids.removeAt(from));
                  if (await perform(
                    context,
                    () => repo.reorderLessons(widget.courseId, ids),
                  ))
                    _reload();
                },
                children: [
                  for (final l in d.lessons)
                    Padding(
                      key: ValueKey(l.id),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: AppCard(
                        onTap: () async {
                          await context.push(
                            '/training/manage/${widget.courseId}/lessons/${l.id}',
                            extra: l,
                          );
                          _reload();
                        },
                        child: Row(
                          children: [
                            Icon(switch (l.kind) {
                              LessonKind.article => LucideIcons.fileText,
                              LessonKind.video => LucideIcons.circlePlay,
                              LessonKind.pdf => LucideIcons.fileDown,
                            }),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l.title,
                                style: context.text.titleSmall,
                              ),
                            ),
                            const Icon(LucideIcons.gripVertical, size: 18),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const Gap(16),
              if (!d.course.published)
                AsyncButton(
                  label: t.publish,
                  icon: LucideIcons.rocket,
                  onPressed: d.lessons.isEmpty
                      ? null
                      : () async {
                          if (await perform(context, () async {
                            await _saveDetails();
                            await repo.publish(
                              widget.courseId,
                              published: true,
                            );
                          }, success: t.courseIsPublished)) {
                            _reload();
                          }
                        },
                )
              else
                AsyncButton(
                  label: t.unpublish,
                  icon: LucideIcons.eyeOff,
                  style: AsyncButtonStyle.outlined,
                  onPressed: () async {
                    if (await perform(
                      context,
                      () => repo.publish(widget.courseId, published: false),
                      success: t.courseIsDraft,
                    ))
                      _reload();
                  },
                ),
              const Gap(8),
              AsyncButton(
                label: t.deleteCourse,
                icon: LucideIcons.trash2,
                style: AsyncButtonStyle.text,
                onPressed: () async {
                  if (!await confirm(
                        context,
                        title: t.deleteCourseTitle,
                        message: t.deleteCourseBody,
                        confirmLabel: t.delete,
                        destructive: true,
                      ) ||
                      !context.mounted)
                    return;
                  if (await perform(
                        context,
                        () => repo.deleteCourse(widget.courseId),
                        success: t.courseDeleted,
                      ) &&
                      context.mounted) {
                    ref.invalidate(coursesProvider);
                    context.pop();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Add or edit one lesson: reading text, a video (file or link) or a PDF.
class LessonEditorScreen extends ConsumerStatefulWidget {
  const LessonEditorScreen({required this.courseId, this.lesson, super.key});

  final String courseId;
  final Lesson? lesson;

  @override
  ConsumerState<LessonEditorScreen> createState() => _LessonEditorScreenState();
}

class _LessonEditorScreenState extends ConsumerState<LessonEditorScreen> {
  late final _title = TextEditingController(text: widget.lesson?.title);
  late final _body = TextEditingController(text: widget.lesson?.body);
  late final _url = TextEditingController(text: widget.lesson?.videoUrl);
  late final _minutes = TextEditingController(
    text: widget.lesson?.minutes?.toString(),
  );
  late LessonKind _kind = widget.lesson?.kind ?? LessonKind.article;
  late String? _mediaId = widget.lesson?.mediaId;
  String? _fileName;
  bool _uploading = false;

  @override
  void dispose() {
    for (final c in [_title, _body, _url, _minutes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _upload() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _kind == LessonKind.pdf ? ['pdf'] : ['mp4'],
    );
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final id = await ref
          .read(mediaRepositoryProvider)
          .upload(bytes, purpose: 'TRAINING', filename: picked.name);
      if (mounted)
        setState(() {
          _mediaId = id;
          _fileName = picked.name;
        });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final body = <String, Object?>{
      'title': _title.text.trim(),
      'kind': _kind.wire,
      'body': _kind == LessonKind.article ? _body.text : '',
      'mediaId': _kind == LessonKind.article ? null : _mediaId,
      'videoUrl':
          _kind == LessonKind.video &&
              _mediaId == null &&
              _url.text.trim().isNotEmpty
          ? _url.text.trim()
          : null,
      'minutes': int.tryParse(_minutes.text.trim()),
    };
    final repo = ref.read(trainingRepositoryProvider);
    final existing = widget.lesson;
    final ok = await perform(
      context,
      () => existing == null
          ? repo.addLesson(widget.courseId, Json.from(body))
          : repo.updateLesson(existing.id, Json.from(body)),
      success: t.saved,
    );
    if (ok && mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lesson == null ? t.addLesson : t.editLesson),
        actions: [
          if (widget.lesson != null)
            IconButton(
              icon: const Icon(LucideIcons.trash2),
              onPressed: () async {
                if (!await confirm(
                      context,
                      title: t.deleteLessonTitle,
                      confirmLabel: t.delete,
                      destructive: true,
                    ) ||
                    !context.mounted)
                  return;
                if (await perform(
                      context,
                      () => ref
                          .read(trainingRepositoryProvider)
                          .deleteLesson(widget.lesson!.id),
                    ) &&
                    context.mounted)
                  context.pop();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<LessonKind>(
            segments: [
              ButtonSegment(
                value: LessonKind.article,
                label: Text(t.lessonArticle),
                icon: const Icon(LucideIcons.fileText),
              ),
              ButtonSegment(
                value: LessonKind.video,
                label: Text(t.lessonVideo),
                icon: const Icon(LucideIcons.circlePlay),
              ),
              ButtonSegment(
                value: LessonKind.pdf,
                label: Text(t.lessonPdf),
                icon: const Icon(LucideIcons.fileDown),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() {
              _kind = s.first;
              _mediaId = null;
              _fileName = null;
            }),
          ),
          const Gap(16),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: t.lessonTitle),
          ),
          const Gap(12),
          if (_kind == LessonKind.article)
            TextField(
              controller: _body,
              minLines: 8,
              maxLines: 20,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: t.lessonText,
                alignLabelWithHint: true,
              ),
            )
          else ...[
            AppCard(
              onTap: _uploading ? null : _upload,
              child: Row(
                children: [
                  Icon(
                    _mediaId == null
                        ? LucideIcons.upload
                        : LucideIcons.circleCheck,
                    color: _mediaId == null ? null : context.status.success,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _uploading
                          ? t.photoUploading
                          : (_fileName ??
                                (_mediaId != null
                                    ? t.fileAttached
                                    : (_kind == LessonKind.pdf
                                          ? t.uploadPdf
                                          : t.uploadVideo))),
                      style: context.text.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            if (_kind == LessonKind.video && _mediaId == null) ...[
              const Gap(12),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: t.orVideoLink,
                  hintText: 'https://…',
                ),
              ),
            ],
          ],
          const Gap(12),
          TextField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: '${t.durationMinutes} (${t.optional})',
            ),
          ),
          const Gap(16),
          AsyncButton(label: t.save, onPressed: _uploading ? null : _save),
        ],
      ),
    );
  }
}

class CourseProgressScreen extends ConsumerWidget {
  const CourseProgressScreen({required this.courseId, super.key});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final progress = ref.watch(courseProgressProvider(courseId));
    return Scaffold(
      appBar: AppBar(title: Text(t.progress)),
      body: AsyncBody(
        value: progress,
        onRetry: () => ref.invalidate(courseProgressProvider(courseId)),
        builder: (p) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(label: t.people, value: '${p.people}'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatTile(
                    label: t.completed,
                    value: '${p.finished}',
                    tone: Tone.success,
                  ),
                ),
              ],
            ),
            SectionHeader(t.progressByPerson),
            for (final r in p.rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(r.name, style: context.text.titleSmall),
                          ),
                          Text(
                            '${r.completed}/${r.total}',
                            style: context.text.bodyMedium,
                          ),
                        ],
                      ),
                      const Gap(8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: r.total == 0 ? 0 : r.completed / r.total,
                          minHeight: 6,
                          backgroundColor: context.status.mutedSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
