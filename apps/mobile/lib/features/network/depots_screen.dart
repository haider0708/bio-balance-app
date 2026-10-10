import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/photo_set.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../media/media_repository.dart';
import '../stock/stock_screens.dart' show StockScreen;
import 'network_models.dart';
import 'network_repository.dart';
import 'region_moves.dart';

void _call(String phone) =>
    launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(' ', '')));

/// The grossistes: warehouses of the regions, with their stock. Responsables see their region's;
/// the admin sees them all and creates them.
class DepotsScreen extends ConsumerWidget {
  const DepotsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final admin = ref.watch(meProvider).role == Role.admin;
    final depots = ref.watch(depotsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.grossistesTitle)),
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: () async {
                await context.push('/depots/new');
                ref.invalidate(depotsProvider);
              },
              icon: const Icon(LucideIcons.plus),
              label: Text(t.depotNew),
            )
          : null,
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
                message: admin ? t.noGrossisteYet : null,
              ),
            ],
          ),
          builder: (list) {
            final regions = {for (final d in list) d.regionName}.toList()
              ..sort();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                for (final region in regions) ...[
                  // One region (a responsable's own) needs no heading.
                  if (regions.length > 1) SectionHeader(region),
                  AutoGrid(
                    minItemWidth: 360,
                    maxColumns: 2,
                    spacing: 8,
                    children: [
                      for (final d in list.where((d) => d.regionName == region))
                        _DepotTile(depot: d),
                    ],
                  ),
                  const Gap(8),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DepotTile extends ConsumerWidget {
  const _DepotTile({required this.depot});

  final Depot depot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final d = depot;
    final phone = d.phone;
    return AppCard(
      onTap: () async {
        await context.push('/depots/${d.id}');
        ref.invalidate(depotsProvider);
      },
      child: Row(
        children: [
          d.photoIds.isEmpty
              ? const IconBadge(LucideIcons.warehouse, size: 52)
              : AuthImage(
                  d.photoIds.first,
                  width: 52,
                  height: 52,
                  radius: 14,
                  placeholderIcon: LucideIcons.warehouse,
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.name, style: context.text.titleSmall),
                Text(
                  d.city,
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
                const Gap(6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (!d.active)
                      StatusChip(t.depotSuspendedLabel, tone: Tone.muted)
                    else if (!d.counted && !d.countPending)
                      StatusChip(t.depotNoStock, tone: Tone.warning)
                    else if (d.countPending)
                      StatusChip(t.depotCountWaiting, tone: Tone.info)
                    else
                      StatusChip(
                        t.depotHolds(d.units, d.products),
                        tone: Tone.success,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (phone != null)
            IconButton.filledTonal(
              tooltip: t.call,
              onPressed: () => _call(phone),
              icon: const Icon(LucideIcons.phone),
            ),
        ],
      ),
    );
  }
}

/// One grossiste: its details and photos on top, then its stock and what each person may do about it.
class DepotScreen extends ConsumerWidget {
  const DepotScreen({required this.depotId, super.key});

  final String depotId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final admin = ref.watch(meProvider).role == Role.admin;
    final depot = ref.watch(depotProvider(depotId));
    return depot.when(
      loading: () => Scaffold(appBar: AppBar(), body: const LoadingState()),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          error: error,
          onRetry: () => ref.invalidate(depotProvider(depotId)),
        ),
      ),
      data: (d) => StockScreen(
        locationId: d.id,
        title: d.name,
        isDepot: true,
        suspended: !d.active,
        header: [
          _DepotCard(depot: d),
          const Gap(12),
        ],
        appBarActions: admin
            ? [
                IconButton(
                  tooltip: t.editDepot,
                  onPressed: () async {
                    await context.push('/depots/${d.id}/edit', extra: d);
                    ref.invalidate(depotProvider(depotId));
                  },
                  icon: const Icon(LucideIcons.pencil),
                ),
                _DepotMenu(depot: d),
              ]
            : const [],
      ),
    );
  }
}

class _DepotCard extends StatelessWidget {
  const _DepotCard({required this.depot});

  final Depot depot;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final phone = depot.phone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (depot.photoIds.isNotEmpty) ...[
          PhotoStrip(ids: depot.photoIds),
          const Gap(12),
        ],
        AppCard(
          child: Column(
            children: [
              InfoRow(t.region, depot.regionName),
              InfoRow(t.address, '${depot.address}, ${depot.city}'),
              if (phone != null) InfoRow(t.phone, phone),
            ],
          ),
        ),
        if (phone != null) ...[
          const Gap(8),
          OutlinedButton.icon(
            onPressed: () => _call(phone),
            icon: const Icon(LucideIcons.phone),
            label: Text(t.call),
          ),
        ],
      ],
    );
  }
}

/// The admin's less common actions on a grossiste: suspend it, bring it back, or remove it.
class _DepotMenu extends ConsumerWidget {
  const _DepotMenu({required this.depot});

  final Depot depot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final repo = ref.read(networkRepositoryProvider);
    return PopupMenuButton<String>(
      onSelected: (action) async {
        if (action == 'toggle') {
          if (await perform(
            context,
            () => repo.setDepotActive(depot.id, active: !depot.active),
            success: t.depotSaved,
          )) {
            ref
              ..invalidate(depotProvider(depot.id))
              ..invalidate(depotsProvider);
          }
        } else if (action == 'move') {
          await moveDepotFlow(context, ref, depot);
        } else if (action == 'remove') {
          final yes = await confirm(
            context,
            title: t.depotRemoveTitle,
            message: t.depotRemoveBody,
            confirmLabel: t.depotRemove,
            destructive: true,
          );
          if (!yes || !context.mounted) return;
          if (await perform(
                context,
                () => repo.deleteDepot(depot.id),
                success: t.depotRemoved,
              ) &&
              context.mounted) {
            ref.invalidate(depotsProvider);
            context.pop();
          }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'toggle',
          child: Text(depot.active ? t.depotSuspend : t.depotReactivate),
        ),
        PopupMenuItem(value: 'move', child: Text(t.moveToRegion)),
        PopupMenuItem(value: 'remove', child: Text(t.depotRemove)),
      ],
    );
  }
}

/// Create or edit a grossiste (admin): its details and up to five photos.
class DepotFormScreen extends ConsumerStatefulWidget {
  const DepotFormScreen({this.existing, super.key});

  final Depot? existing;

  @override
  ConsumerState<DepotFormScreen> createState() => _DepotFormScreenState();
}

class _DepotFormScreenState extends ConsumerState<DepotFormScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _city = TextEditingController(text: widget.existing?.city);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late String? _regionId = widget.existing?.regionId;
  late List<String> _photoIds = widget.existing?.photoIds ?? const [];
  bool _photosBusy = false;

  @override
  void dispose() {
    for (final c in [_name, _address, _city, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final t = AppLocalizations.of(context);
    final existing = widget.existing;
    final phone = _phone.text.trim();
    final ok = await perform(
      context,
      () => ref
          .read(networkRepositoryProvider)
          .saveDepot(
            existing?.id,
            name: _name.text.trim(),
            address: _address.text.trim(),
            city: _city.text.trim(),
            phone: phone.isEmpty ? null : phone,
            regionId: _regionId,
            photoIds: _photoIds,
          ),
      success: t.depotSaved,
    );
    if (!ok || !mounted) return;
    ref.invalidate(depotsProvider);
    if (existing != null) ref.invalidate(depotProvider(existing.id));
    context.pop();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? AppLocalizations.of(context).fieldRequired
      : null;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final editing = widget.existing != null;
    final regions = ref.watch(regionsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(editing ? t.editDepot : t.depotNew)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t.depotName),
              validator: _required,
            ),
            const Gap(12),
            if (!editing) ...[
              AsyncBody(
                value: regions,
                onRetry: () => ref.invalidate(regionsProvider),
                builder: (list) => DropdownButtonFormField<String>(
                  initialValue: _regionId,
                  decoration: InputDecoration(labelText: t.region),
                  items: [
                    for (final r in list)
                      DropdownMenuItem(value: r.id, child: Text(r.name)),
                  ],
                  validator: (v) => v == null ? t.fieldRequired : null,
                  onChanged: (v) => setState(() => _regionId = v),
                ),
              ),
              const Gap(12),
            ],
            TextFormField(
              controller: _address,
              decoration: InputDecoration(labelText: t.depotAddress),
              validator: _required,
            ),
            const Gap(12),
            TextFormField(
              controller: _city,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: t.city),
              validator: _required,
            ),
            const Gap(12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: '${t.phone} (${t.optional})',
              ),
            ),
            SectionHeader(t.depotPhotos),
            PhotoSet(
              label: t.depotPhotosAdd,
              initialIds: widget.existing?.photoIds ?? const [],
              onChanged: (ids, busy) => setState(() {
                _photoIds = ids;
                _photosBusy = busy;
              }),
            ),
            const Gap(24),
            AsyncButton(
              label: t.save,
              icon: LucideIcons.check,
              onPressed: _photosBusy ? null : _save,
            ),
          ],
        ),
      ),
    );
  }
}
