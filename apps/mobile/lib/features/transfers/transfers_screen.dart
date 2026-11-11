import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/async_body.dart';
import '../../core/widgets/list_tools.dart';
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
  String _query = '';
  DocSort _sort = DocSort.newest;

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
            ListToolbar(
              padding: const EdgeInsets.only(bottom: 8),
              hint: t.searchTransfers,
              onSearch: (v) => setState(() => _query = v),
              sort: SortMenu<DocSort>(
                value: _sort,
                onChanged: (v) => setState(() => _sort = v),
                options: DocSort.options(t),
              ),
            ),
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
                final inTab = all.where((x) => x.pending == _waiting).toList();
                final shown =
                    inTab
                        .where(
                          (x) => matchesSearch(_query, [
                            x.number,
                            x.from.name,
                            x.to.name,
                            x.groupName,
                            x.createdBy,
                            ...x.lines.map((l) => l.name),
                          ]),
                        )
                        .toList()
                      ..sort(
                        (a, b) => _sort.compare(
                          a.createdAt,
                          a.units,
                          b.createdAt,
                          b.units,
                        ),
                      );
                if (shown.isEmpty) {
                  return _query.isNotEmpty && inTab.isNotEmpty
                      ? EmptyState(icon: LucideIcons.search, title: t.noResults)
                      : EmptyState(
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
