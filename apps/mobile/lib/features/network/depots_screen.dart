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
                onTap: () => context.push('/stock/${d.id}', extra: d.name),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.colors.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        LucideIcons.warehouse,
                        color: context.colors.primary,
                      ),
                    ),
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
