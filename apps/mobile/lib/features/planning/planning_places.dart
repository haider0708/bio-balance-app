import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/async_body.dart';
import '../../l10n/app_localizations.dart';

import '../network/network_models.dart';
import '../network/network_repository.dart';

/// A store or a grossiste of the responsable's region, to plan a visit to.
class PlaceOption {
  const PlaceOption({
    required this.isDepot,
    required this.id,
    required this.name,
    required this.subtitle,
  });

  final bool isDepot;
  final String id;
  final String name;
  final String subtitle;

  String get kindWire => isDepot ? 'DEPOT' : 'PDV';
}

final placeOptionsProvider = FutureProvider.autoDispose<List<PlaceOption>>((
  ref,
) async {
  final pdvs = await ref.watch(pdvsProvider(null).future);
  final depots = await ref.watch(depotsProvider.future);
  return [
    for (final p in pdvs)
      if (p.status == ItemStatus.active)
        PlaceOption(
          isDepot: false,
          id: p.id,
          name: p.name,
          subtitle: [p.address, p.city].where((s) => s.isNotEmpty).join(', '),
        ),
    for (final d in depots)
      if (d.active)
        PlaceOption(
          isDepot: true,
          id: d.id,
          name: d.name,
          subtitle: [d.address, d.city].where((s) => s.isNotEmpty).join(', '),
        ),
  ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
});

/// A list to choose one place from (the visit form).
class PlacePickerSheet extends ConsumerWidget {
  const PlacePickerSheet({super.key});

  static Future<PlaceOption?> show(BuildContext context) =>
      showModalBottomSheet<PlaceOption>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const PlacePickerSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final places = ref.watch(placeOptionsProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (context, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(t.visitChoosePlace, style: context.text.titleLarge),
          ),
          const Divider(),
          Expanded(
            child: AsyncBody<List<PlaceOption>>(
              value: places,
              onRetry: () => ref.invalidate(placeOptionsProvider),
              builder: (list) => ListView(
                controller: scroll,
                children: [
                  for (final p in list)
                    ListTile(
                      leading: Icon(
                        p.isDepot ? LucideIcons.warehouse : LucideIcons.store,
                      ),
                      title: Text(p.name),
                      subtitle: Text(p.subtitle),
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
