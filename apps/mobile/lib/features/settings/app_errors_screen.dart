import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';

class AppError {
  const AppError({
    required this.platform,
    required this.version,
    required this.message,
    required this.stack,
    required this.count,
    required this.lastSeen,
  });

  factory AppError.fromJson(Json j) => AppError(
    platform: j.str('platform'),
    version: j.str('appVersion'),
    message: j.str('message'),
    stack: j.str('stack'),
    count: j.integer('count'),
    lastSeen: DateTime.parse(j.str('lastSeen')).toLocal(),
  );

  final String platform;
  final String version;
  final String message;
  final String stack;
  final int count;
  final DateTime lastSeen;
}

final appErrorsProvider = FutureProvider.autoDispose<List<AppError>>((
  ref,
) async {
  final rows = await ref.watch(apiClientProvider).get('/v1/client-errors');
  return [for (final r in rows as List) AppError.fromJson(r as Json)];
});

/// The admin's view of the errors the app met on phones and in the console (last 30 days).
class AppErrorsScreen extends ConsumerWidget {
  const AppErrorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final errors = ref.watch(appErrorsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.appErrorsTitle)),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(appErrorsProvider.future),
        child: AsyncBody(
          value: errors,
          onRetry: () => ref.invalidate(appErrorsProvider),
          isEmpty: (list) => list.isEmpty,
          empty: ListView(
            children: [
              EmptyState(
                icon: LucideIcons.circleCheck,
                title: t.appErrorsNone,
                message: t.appErrorsHint,
              ),
            ],
          ),
          builder: (list) => ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (context, i) => _ErrorCard(list[i]),
          ),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.error);

  final AppError error;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final platform = switch (error.platform) {
      'ios' => 'iPhone',
      'web' => t.appErrorsWeb,
      _ => 'Android',
    };
    return AppCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          error.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.titleSmall,
        ),
        subtitle: Text(
          '$platform · ${error.version} · '
          '${t.appErrorsTimes(error.count)} · '
          '${Dates.dateTime(error.lastSeen, t.localeName)}',
          style: context.text.bodySmall?.copyWith(color: context.status.muted),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          SelectableText(
            error.stack.isEmpty ? error.message : error.stack,
            style: context.text.bodySmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
