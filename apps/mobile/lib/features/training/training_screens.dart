import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/config.dart';
import '../../core/files/files.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../media/media_repository.dart';
import 'training_models.dart';
import 'training_repository.dart';

class CoursesScreen extends ConsumerWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final courses = ref.watch(coursesProvider);
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.trainingTitle),
        actions: [
          if (me.role == Role.admin)
            IconButton(
              tooltip: t.manageTraining,
              onPressed: () => context.push('/training/manage'),
              icon: const Icon(LucideIcons.settings2),
            ),
        ],
      ),
      body: AsyncBody(
        value: courses,
        onRetry: () => ref.invalidate(coursesProvider),
        isEmpty: (list) => list.where((c) => c.published).isEmpty,
        empty: EmptyState(
          icon: LucideIcons.graduationCap,
          title: t.noCourses,
          message: t.noCoursesHint,
        ),
        builder: (list) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(coursesProvider);
            await ref.read(coursesProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final c in list.where((c) => c.published))
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CourseCard(
                    course: c,
                    onTap: () => context.push('/training/${c.id}'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CourseCard extends StatelessWidget {
  const CourseCard({
    required this.course,
    required this.onTap,
    this.showStatus = false,
    super.key,
  });

  final Course course;
  final VoidCallback onTap;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (course.coverId != null)
            AuthImage(
              course.coverId,
              height: 130,
              width: double.infinity,
              radius: 14,
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        course.title,
                        style: context.text.titleMedium,
                      ),
                    ),
                    if (showStatus)
                      StatusChip(
                        course.published ? t.published : t.draft,
                        tone: course.published ? Tone.success : Tone.muted,
                      ),
                    if (!showStatus && course.done)
                      StatusChip(
                        t.completed,
                        tone: Tone.success,
                        icon: LucideIcons.check,
                      ),
                  ],
                ),
                if (course.summary.isNotEmpty) ...[
                  const Gap(4),
                  Text(
                    course.summary,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.status.muted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const Gap(12),
                // The admin manages a course (who it is for, how long it is); a learner follows their progress.
                if (!showStatus) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: course.progress,
                      minHeight: 6,
                      backgroundColor: context.status.mutedSoft,
                    ),
                  ),
                  const Gap(8),
                ],
                Text(
                  showStatus
                      ? [
                          t.lessonCountLabel(course.lessonCount),
                          if (course.minutes > 0) t.minutes(course.minutes),
                          _audience(t, course),
                        ].join(' · ')
                      : '${t.lessonsDone(course.completedCount, course.lessonCount)}${course.minutes > 0 ? ' · ${t.minutes(course.minutes)}' : ''}',
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CourseScreen extends ConsumerWidget {
  const CourseScreen({required this.courseId, super.key});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final detail = ref.watch(courseProvider(courseId));
    return Scaffold(
      appBar: AppBar(
        title: Text(detail.value?.course.title ?? t.trainingTitle),
      ),
      body: AsyncBody(
        value: detail,
        onRetry: () => ref.invalidate(courseProvider(courseId)),
        builder: (d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (d.course.summary.isNotEmpty)
              Text(d.course.summary, style: context.text.bodyLarge),
            const Gap(8),
            for (final lesson in d.lessons)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AppCard(
                  onTap: () async {
                    await context.push(
                      '/training/$courseId/lessons/${lesson.id}',
                    );
                    ref.invalidate(courseProvider(courseId));
                    ref.invalidate(coursesProvider);
                  },
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: lesson.done
                              ? context.status.successSoft
                              : context.colors.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          lesson.done ? LucideIcons.check : _icon(lesson.kind),
                          size: 20,
                          color: context.colors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(lesson.title, style: context.text.titleSmall),
                            Text(
                              [
                                _kind(t, lesson.kind),
                                if (lesson.minutes != null)
                                  t.minutes(lesson.minutes!),
                              ].join(' · '),
                              style: context.text.bodySmall?.copyWith(
                                color: context.status.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        LucideIcons.chevronRight,
                        size: 18,
                        color: context.status.muted,
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

IconData _icon(LessonKind k) => switch (k) {
  LessonKind.article => LucideIcons.fileText,
  LessonKind.video => LucideIcons.circlePlay,
  LessonKind.pdf => LucideIcons.fileDown,
};

String _kind(AppLocalizations t, LessonKind k) => switch (k) {
  LessonKind.article => t.lessonArticle,
  LessonKind.video => t.lessonVideo,
  LessonKind.pdf => t.lessonPdf,
};

class LessonScreen extends ConsumerWidget {
  const LessonScreen({
    required this.courseId,
    required this.lessonId,
    super.key,
  });

  final String courseId;
  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final detail = ref.watch(courseProvider(courseId));
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(),
      body: AsyncBody(
        value: detail,
        onRetry: () => ref.invalidate(courseProvider(courseId)),
        builder: (d) {
          final index = d.lessons.indexWhere((l) => l.id == lessonId);
          if (index < 0)
            return EmptyState(
              icon: LucideIcons.fileQuestionMark,
              title: t.errorGeneric,
            );
          final lesson = d.lessons[index];
          final next = index + 1 < d.lessons.length
              ? d.lessons[index + 1]
              : null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(lesson.title, style: context.text.headlineSmall),
              const Gap(16),
              switch (lesson.kind) {
                LessonKind.article => SelectableText(
                  lesson.body,
                  style: context.text.bodyLarge?.copyWith(height: 1.6),
                ),
                LessonKind.video => _Video(lesson: lesson),
                LessonKind.pdf => _Pdf(lesson: lesson),
              },
              const Gap(28),
              if (me.role != Role.admin)
                AsyncButton(
                  label: lesson.done ? t.markNotDone : t.markDone,
                  icon: lesson.done ? LucideIcons.undo2 : LucideIcons.check,
                  style: lesson.done
                      ? AsyncButtonStyle.outlined
                      : AsyncButtonStyle.filled,
                  onPressed: () async {
                    final ok = await perform(
                      context,
                      () => ref
                          .read(trainingRepositoryProvider)
                          .setLessonDone(lesson.id, !lesson.done),
                    );
                    if (!ok) return;
                    ref.invalidate(courseProvider(courseId));
                    if (!lesson.done && next != null && context.mounted)
                      context.pushReplacement(
                        '/training/$courseId/lessons/${next.id}',
                      );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Video extends ConsumerStatefulWidget {
  const _Video({required this.lesson});

  final Lesson lesson;

  @override
  ConsumerState<_Video> createState() => _VideoState();
}

class _VideoState extends ConsumerState<_Video> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    final mediaId = widget.lesson.mediaId;
    if (mediaId != null) unawaited(_open(mediaId));
  }

  Future<void> _open(String mediaId) async {
    try {
      // A browser cannot send the sign-in header with a video, so it plays the downloaded file.
      final local = kIsWeb
          ? localObjectUrl(
              await ref.read(mediaRepositoryProvider).bytes(mediaId),
              'video/mp4',
            )
          : null;
      if (!mounted) return;
      final controller = local != null
          ? VideoPlayerController.networkUrl(Uri.parse(local))
          : VideoPlayerController.networkUrl(
              Uri.parse('${AppConfig.apiBaseUrl}/v1/media/$mediaId'),
              httpHeaders: {
                'Authorization': 'Bearer ${ref.read(tokenProvider)}',
              },
            );
      _controller = controller;
      await controller.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final url = widget.lesson.videoUrl;
    if (_controller == null) {
      return FilledButton.icon(
        onPressed: url == null
            ? null
            : () => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              ),
        icon: const Icon(LucideIcons.externalLink),
        label: Text(t.openVideo),
      );
    }
    final c = _controller!;
    if (_error != null) return Text(t.videoUnavailable);
    if (!c.value.isInitialized)
      return const AspectRatio(aspectRatio: 16 / 9, child: LoadingState());
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
        ),
        const Gap(8),
        VideoProgressIndicator(c, allowScrubbing: true),
        ValueListenableBuilder(
          valueListenable: c,
          builder: (context, value, _) => IconButton.filledTonal(
            iconSize: 32,
            onPressed: () => value.isPlaying ? c.pause() : c.play(),
            icon: Icon(value.isPlaying ? LucideIcons.pause : LucideIcons.play),
          ),
        ),
      ],
    );
  }
}

class _Pdf extends ConsumerWidget {
  const _Pdf({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return AsyncButton(
      label: t.openDocument,
      icon: LucideIcons.fileText,
      onPressed: lesson.mediaId == null
          ? null
          : () async {
              await perform(context, () async {
                final bytes = await ref
                    .read(mediaRepositoryProvider)
                    .bytes(lesson.mediaId!);
                await viewFile('${lesson.id}.pdf', bytes, 'application/pdf');
              });
            },
    );
  }
}

/// Who a course is for, in words.
String _audience(AppLocalizations t, Course course) {
  if (course.audienceRoles.isEmpty) return t.audienceEveryone;
  return course.audienceRoles
      .map(
        (r) => switch (r) {
          'RESPONSABLE' => t.roleResponsable,
          _ => t.roleVendeurShort,
        },
      )
      .join(', ');
}
