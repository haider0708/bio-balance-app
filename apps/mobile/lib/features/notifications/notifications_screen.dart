import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/paged_list.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import 'notification_models.dart';
import 'notifications_repository.dart';

/// Where a notification leads, for each kind of thing and each role. Null when nowhere useful.
String? routeForEntity(Role role, String? type, String? id) {
  if (type == null || id == null) return null;
  return switch ((type, role)) {
    ('RestockOrder', _) => '/restocks/$id',
    ('StockRecount', Role.admin) => '/approvals',
    ('Location', _) => '/stock/$id',
    ('StockDeclaration', Role.admin) => '/approvals',
    ('StockDeclaration', _) => '/stock/declarations/$id',
    ('Pdv', Role.admin) || ('Pdv', Role.responsable) => '/pdvs/$id',
    ('Group', Role.admin) => '/approvals',
    ('User', Role.admin) => '/approvals',
    ('Sale', Role.vendeur) => '/sales/$id',
    ('PayoutRequest', Role.admin) => '/payouts',
    ('PayoutRequest', Role.vendeur) => '/wallet',
    _ => null,
  };
}

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  List<AppNotification> _pinned = const [];

  /// null shows everything; 'UNREAD' only what was not read; otherwise a category.
  String? _filter;
  late PagedController<AppNotification> _paged = _make();

  PagedController<AppNotification> _make() => PagedController((cursor) async {
    final page = await ref
        .read(notificationsRepositoryProvider)
        .page(
          cursor: cursor,
          category: _filter == 'UNREAD' ? null : _filter,
          unreadOnly: _filter == 'UNREAD',
        );
    if (cursor == null && mounted) {
      setState(() => _pinned = _filter == null ? page.pinned : const []);
    }
    return PageResult(page.items, page.nextCursor);
  });

  void _choose(String? filter) {
    if (filter == _filter) return;
    _paged.dispose();
    setState(() {
      _filter = filter;
      _paged = _make();
    });
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  Future<void> _open(AppNotification n) async {
    final me = ref.read(meProvider);
    if (n.unread) {
      await ref
          .read(notificationsRepositoryProvider)
          .markRead(n.id)
          .catchError((Object _) {});
      unawaited(ref.read(unreadCountProvider.notifier).refresh());
      await _paged.refresh();
    }
    if (!mounted) return;
    if (n.isMessage) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _MessageSheet(notification: n),
      );
      return;
    }
    final route = routeForEntity(me.role, n.entityType, n.entityId);
    if (route != null) await context.push<void>(route);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.notificationsTitle),
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await perform(
                context,
                () => ref.read(notificationsRepositoryProvider).markAllRead(),
              );
              if (ok) {
                unawaited(ref.read(unreadCountProvider.notifier).refresh());
                await _paged.refresh();
              }
            },
            child: Text(t.markAllRead),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              children: [
                for (final (value, label) in _filters(
                  t,
                  ref.read(meProvider).role,
                ))
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == value,
                      onSelected: (_) => _choose(value),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _list(t)),
        ],
      ),
    );
  }

  List<(String?, String)> _filters(AppLocalizations t, Role role) => [
    (null, t.all),
    ('UNREAD', t.unreadFilter),
    if (role == Role.responsable) ('SALES', t.filterSales),
    if (role != Role.vendeur) ('STOCK', t.filterStock),
    if (role != Role.vendeur) ('RESTOCKS', t.filterRestocks),
    if (role == Role.admin || role == Role.vendeur)
      ('PAYMENTS', t.filterPayments),
    if (role == Role.admin || role == Role.responsable)
      ('NETWORK', t.filterNetwork),
    ('MESSAGES', t.filterMessages),
  ];

  Widget _list(AppLocalizations t) {
    return PagedList<AppNotification>(
      controller: _paged,
      empty: EmptyState(
        icon: LucideIcons.bellOff,
        title: t.noNotifications,
        message: t.noNotificationsHint,
      ),
      header: _pinned.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  t.pinned,
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                ),
                for (final n in _pinned)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _Tile(notification: n, onTap: () => _open(n)),
                  ),
                SectionHeader(
                  t.recent,
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                ),
              ],
            ),
      itemBuilder: (context, n, _) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: _Tile(notification: n, onTap: () => _open(n)),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final n = notification;
    final icon = n.isMessage
        ? LucideIcons.megaphone
        : switch (n.entityType) {
            'RestockOrder' => LucideIcons.truck,
            'StockDeclaration' => LucideIcons.boxes,
            'Pdv' || 'Group' => LucideIcons.store,
            'User' => LucideIcons.userRound,
            'Sale' => LucideIcons.receipt,
            'PayoutRequest' => LucideIcons.banknote,
            _ => LucideIcons.bell,
          };
    return AppCard(
      onTap: onTap,
      color: n.unread
          ? context.colors.primaryContainer.withValues(alpha: 0.45)
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: n.isMessage
                  ? context.status.infoSoft
                  : context.colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 20,
              color: n.isMessage ? context.status.info : context.colors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  n.headline(t.localeName),
                  style: context.text.titleSmall?.copyWith(
                    fontWeight: n.unread ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (n.isMessage && (n.body ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    n.body!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  Dates.dateTime(n.createdAt, t.localeName),
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ],
            ),
          ),
          if (n.unread)
            Container(
              margin: const EdgeInsets.only(top: 6, left: 8),
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: context.colors.primary,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

class _MessageSheet extends StatelessWidget {
  const _MessageSheet({required this.notification});

  final AppNotification notification;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.title ?? '', style: context.text.titleLarge),
            const Gap(4),
            Text(
              Dates.dateTime(notification.createdAt, t.localeName),
              style: context.text.bodySmall?.copyWith(
                color: context.status.muted,
              ),
            ),
            const Gap(16),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  notification.body ?? '',
                  style: context.text.bodyLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
