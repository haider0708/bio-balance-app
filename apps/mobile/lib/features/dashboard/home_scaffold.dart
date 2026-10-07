import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../notifications/notifications_repository.dart';

/// The top of every home tab: a soft brand glow, the greeting, and round buttons for
/// notifications (with the unread badge) and settings.
class HomeScaffold extends ConsumerWidget {
  const HomeScaffold({
    required this.title,
    required this.body,
    required this.onRefresh,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final unread = ref.watch(unreadCountProvider);
    final s = context.status;
    return Scaffold(
      body: Stack(
        children: [
          // The glow: brand colour fading down behind the greeting, edge to edge.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 300,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [s.glow, s.glow.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: context.text.headlineSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                style: context.text.bodyMedium?.copyWith(
                                  color: s.muted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _RoundButton(
                        tooltip: t.notificationsTitle,
                        onTap: () => context.push('/notifications'),
                        child: Badge(
                          isLabelVisible: unread > 0,
                          label: Text(unread > 99 ? '99+' : '$unread'),
                          child: const Icon(LucideIcons.bell, size: 21),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RoundButton(
                        tooltip: t.settingsTitle,
                        onTap: () => context.push('/settings'),
                        child: const Icon(LucideIcons.settings2, size: 21),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(onRefresh: onRefresh, child: body),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: s.card,
        shape: CircleBorder(side: BorderSide(color: s.hairline)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 46, height: 46, child: Center(child: child)),
        ),
      ),
    );
  }
}
