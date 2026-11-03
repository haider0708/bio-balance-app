import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/async_body.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import 'transfer_models.dart';
import 'transfer_widgets.dart';
import 'transfers_repository.dart';

/// The transfers a person may see: what waits for the admin, and what was decided.
class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  bool _waiting = true;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final transfers = ref.watch(transfersProvider(null));
    return Scaffold(
      appBar: AppBar(title: Text(t.transfersTitle)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () async {
          await context.push('/transfers/new');
          ref.invalidate(transfersProvider);
        },
        icon: const Icon(LucideIcons.plus),
        label: Text(t.transferNew),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(transfersProvider(null));
          await ref.read(transfersProvider(null).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text(t.transferWaitingTab),
                  selected: _waiting,
                  onSelected: (_) => setState(() => _waiting = true),
                ),
                ChoiceChip(
                  label: Text(t.transferDecidedTab),
                  selected: !_waiting,
                  onSelected: (_) => setState(() => _waiting = false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AsyncBody<List<Transfer>>(
              value: transfers,
              onRetry: () => ref.invalidate(transfersProvider(null)),
              builder: (all) {
                final shown = all.where((x) => x.pending == _waiting).toList();
                if (shown.isEmpty) {
                  return EmptyState(
                    icon: LucideIcons.arrowLeftRight,
                    title: t.transferNone,
                    message: t.transferNoneHint,
                  );
                }
                return Column(
                  spacing: 12,
                  children: [
                    for (final x in shown)
                      TransferCard(
                        transfer: x,
                        onTap: () async {
                          await context.push('/transfers/${x.id}');
                          ref.invalidate(transfersProvider);
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
