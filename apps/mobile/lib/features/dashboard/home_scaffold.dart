import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../notifications/notifications_repository.dart';

/// The top of every home tab: greeting, notification bell with its badge, and settings.
class HomeScaffold extends ConsumerWidget {
  const HomeScaffold({required this.title, required this.body, required this.onRefresh, this.subtitle, super.key});

  final String title;
  final String? subtitle;
  final Widget body;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final unread = ref.watch(unreadCountProvider);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: context.text.headlineSmall),
            if (subtitle != null) Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: context.status.muted)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t.notificationsTitle,
            onPressed: () => context.push('/notifications'),
            icon: Badge(isLabelVisible: unread > 0, label: Text(unread > 99 ? '99+' : '$unread'), child: const Icon(LucideIcons.bell)),
          ),
          IconButton(tooltip: t.settingsTitle, onPressed: () => context.push('/settings'), icon: const Icon(LucideIcons.settings)),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(onRefresh: onRefresh, child: body),
    );
  }
}
