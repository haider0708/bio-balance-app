import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import 'planning_models.dart';
import 'planning_repository.dart';

const _leads = [0, 15, 30, 60, 120];

/// When to be reminded, and the link that puts the visits in the phone's calendar app.
class PlanningSettingsScreen extends ConsumerWidget {
  const PlanningSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final prefs = ref.watch(planningPreferencesProvider);
    final link = ref.watch(calendarLinkProvider);

    Future<void> save(Map<String, Object?> body) async {
      final ok = await perform(
        context,
        () => ref.read(planningRepositoryProvider).setPreferences(body),
      );
      if (ok) ref.invalidate(planningPreferencesProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.planningSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionHeader(t.reminderBefore),
          AsyncBody<PlanningPreferences>(
            value: prefs,
            onRetry: () => ref.invalidate(planningPreferencesProvider),
            builder: (p) => AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final m in _leads)
                        ChoiceChip(
                          label: Text(
                            m == 0 ? t.reminderNone : t.reminderMinutes(m),
                          ),
                          selected: p.leadMinutes == m,
                          onSelected: (_) => save({'leadMinutes': m}),
                        ),
                    ],
                  ),
                  const Gap(8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.eveningSummary),
                    value: p.eveningSummary,
                    onChanged: (v) => save({'eveningSummary': v}),
                  ),
                ],
              ),
            ),
          ),
          SectionHeader(t.calendarTitle),
          AsyncBody<CalendarLink>(
            value: link,
            onRetry: () => ref.invalidate(calendarLinkProvider),
            builder: (l) => AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 12,
                children: [
                  Text(t.calendarBody, style: context.text.bodyMedium),
                  FilledButton.icon(
                    onPressed: () => launchUrl(
                      Uri.parse(l.webcal),
                      mode: LaunchMode.externalApplication,
                    ),
                    icon: const Icon(LucideIcons.calendarPlus),
                    label: Text(t.calendarAdd),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: l.url));
                          if (context.mounted) {
                            showMessage(context, t.calendarCopied);
                          }
                        },
                        icon: const Icon(LucideIcons.copy, size: 16),
                        label: Text(t.calendarCopy),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          if (!await confirm(
                            context,
                            title: t.calendarRenew,
                            message: t.calendarRenewAsk,
                          )) {
                            return;
                          }
                          if (!context.mounted) return;
                          final ok = await perform(
                            context,
                            () => ref
                                .read(planningRepositoryProvider)
                                .calendarLink(rotate: true),
                          );
                          if (ok) ref.invalidate(calendarLinkProvider);
                        },
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                        label: Text(t.calendarRenew),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Gap(16),
          Text(
            t.locationPrivacy,
            style: context.text.bodySmall?.copyWith(
              color: context.status.muted,
            ),
          ),
        ],
      ),
    );
  }
}
