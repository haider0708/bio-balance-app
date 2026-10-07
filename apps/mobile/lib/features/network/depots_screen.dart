import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/widgets/feedback.dart';
import '../stock/stock_repository.dart';
import '../stock/stock_screens.dart' show StockTile;
import 'network_models.dart';
import 'network_repository.dart';

/// The grossistes and their depots, with a phone number to call when stock is needed.
class DepotsScreen extends ConsumerWidget {
  const DepotsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final depots = ref.watch(depotsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.grossistesTitle)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(depotsProvider);
          await ref.read(depotsProvider.future);
        },
        child: AsyncBody(
          value: depots,
          onRetry: () => ref.invalidate(depotsProvider),
          isEmpty: (l) => l.isEmpty,
          empty: ListView(
            children: [
              EmptyState(
                icon: LucideIcons.warehouse,
                title: t.noGrossisteShort,
              ),
            ],
          ),
          builder: (list) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: list.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (context, i) {
              final d = list[i];
              final phone = d.grossistePhone ?? d.phone;
              return AppCard(
                onTap: () => ref.read(meProvider).role == Role.admin
                    ? context.push('/depots/${d.id}', extra: d)
                    : context.push('/stock/${d.id}', extra: d.name),
                child: Row(
                  children: [
                    const IconBadge(LucideIcons.warehouse, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(d.name, style: context.text.titleSmall),
                          Text(
                            [
                              ?d.grossisteName,
                              d.city,
                              ?d.regionName,
                            ].join(' · '),
                            style: context.text.bodySmall?.copyWith(
                              color: context.status.muted,
                            ),
                          ),
                          if (phone != null)
                            Text(phone, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    if (phone != null)
                      IconButton.filledTonal(
                        tooltip: t.call,
                        onPressed: () => launchUrl(
                          Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
                        ),
                        icon: const Icon(LucideIcons.phone),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A grossiste as the admin sees them: details to edit, and the stock to correct.
class DepotScreen extends ConsumerWidget {
  const DepotScreen({required this.depot, super.key});

  final Depot depot;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final t = AppLocalizations.of(context);
    final name = TextEditingController(text: depot.name);
    final address = TextEditingController(text: depot.address);
    final city = TextEditingController(text: depot.city);
    final phone = TextEditingController(text: depot.phone ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.editDepot),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: t.depotName),
              ),
              const Gap(10),
              TextField(
                controller: address,
                decoration: InputDecoration(labelText: t.address),
              ),
              const Gap(10),
              TextField(
                controller: city,
                decoration: InputDecoration(labelText: t.city),
              ),
              const Gap(10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t.phone),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t.save),
          ),
        ],
      ),
    );
    if (save != true || !context.mounted) return;
    if (await perform(
      context,
      () => ref
          .read(networkRepositoryProvider)
          .updateDepot(
            depot.id,
            name: name.text.trim(),
            address: address.text.trim(),
            city: city.text.trim(),
            phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
          ),
      success: t.saved,
    )) {
      ref.invalidate(depotsProvider);
      if (context.mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final levels = ref.watch(stockLevelsProvider(depot.id));
    final phone = depot.grossistePhone ?? depot.phone;
    return Scaffold(
      appBar: AppBar(
        title: Text(depot.name),
        actions: [
          IconButton(
            tooltip: t.editDepot,
            onPressed: () => _edit(context, ref),
            icon: const Icon(LucideIcons.pencil),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(stockLevelsProvider(depot.id));
          await ref.read(stockLevelsProvider(depot.id).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            AppCard(
              child: Column(
                children: [
                  InfoRow(t.grossisteLabel, depot.grossisteName ?? '—'),
                  if (depot.regionName != null)
                    InfoRow(t.region, depot.regionName!),
                  InfoRow(t.address, '${depot.address}, ${depot.city}'),
                  if (depot.grossisteEmail != null)
                    InfoRow(t.email, depot.grossisteEmail!),
                  if (phone != null) InfoRow(t.phone, phone),
                ],
              ),
            ),
            if (phone != null) ...[
              const Gap(8),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri(scheme: 'tel', path: phone.replaceAll(' ', '')),
                ),
                icon: const Icon(LucideIcons.phone),
                label: Text(t.call),
              ),
            ],
            SectionHeader(t.stockLevels),
            AsyncBody(
              value: levels,
              onRetry: () => ref.invalidate(stockLevelsProvider(depot.id)),
              builder: (data) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          icon: LucideIcons.boxes,
                          label: t.totalUnits,
                          value: '${data.units}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          icon: LucideIcons.package,
                          label: t.products,
                          value: '${data.items.length}',
                        ),
                      ),
                    ],
                  ),
                  const Gap(8),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await context.push(
                        '/stock/${depot.id}/adjust',
                        extra: depot.name,
                      );
                      ref.invalidate(stockLevelsProvider(depot.id));
                    },
                    icon: const Icon(LucideIcons.slidersHorizontal),
                    label: Text(t.adjustStock),
                  ),
                  const Gap(8),
                  if (data.items.isEmpty)
                    EmptyState(icon: LucideIcons.boxes, title: t.noStockYet),
                  for (final item in data.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: StockTile(item: item),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
