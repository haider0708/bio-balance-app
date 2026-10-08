import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import '../notifications/notifications_repository.dart';
import 'dashboard_repository.dart';
import 'home_scaffold.dart';

class GrossisteHome extends ConsumerWidget {
  const GrossisteHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final data = ref.watch(dashboardProvider(null));
    return HomeScaffold(
      title: t.helloName(me.name.split(' ').first),
      subtitle: me.depot?.name,
      onRefresh: () async {
        ref.invalidate(dashboardProvider(null));
        unawaited(ref.read(unreadCountProvider.notifier).refresh());
        await ref.read(dashboardProvider(null).future);
      },
      body: AsyncBody(
        value: data,
        onRetry: () => ref.invalidate(dashboardProvider(null)),
        builder: (d) {
          final toShip = d.integer('toShip');
          final mine = d.obj('myRestocks');
          final stock = d.obj('stock');
          final last = d.objOrNull('lastDeclaration');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              AppCard(
                onTap: () => context.go('/orders'),
                color: toShip > 0
                    ? Theme.of(context).colorScheme.primary
                    : null,
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.truck,
                      size: 30,
                      color: toShip > 0
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        toShip > 0
                            ? t.ordersToPrepare(toShip)
                            : t.noOrdersToPrepare,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: toShip > 0
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : null,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      icon: LucideIcons.boxes,
                      label: t.totalUnits,
                      value: '${stock.integer('units')}',
                      onTap: () => context.go('/stock'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      icon: LucideIcons.package,
                      label: t.products,
                      value: '${stock.integer('products')}',
                      onTap: () => context.go('/stock'),
                    ),
                  ),
                ],
              ),
              if (last == null || last.str('status') != 'APPROVED') ...[
                const Gap(12),
                AppCard(
                  onTap: () => context.go('/stock'),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.camera),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          last == null
                              ? t.grossisteDeclareFirst
                              : (last.str('status') == 'PENDING'
                                    ? t.declarationWaiting
                                    : t.declarationRejectedRetry),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const Gap(12),
              AppCard(
                onTap: () => context.go('/orders'),
                child: Row(
                  children: [
                    const Icon(LucideIcons.packagePlus),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        t.myRestockRequests(
                          mine.integer('REQUESTED') +
                              mine.integer('SHIPPED') +
                              mine.integer('RECEIVED'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
