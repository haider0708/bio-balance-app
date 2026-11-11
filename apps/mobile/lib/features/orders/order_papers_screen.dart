import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/photo_set.dart';
import '../../l10n/app_localizations.dart';
import '../restock/restock_models.dart';
import '../restock/restock_repository.dart';

/// Papers added to an order (invoice, preparation or delivery note): photos or a PDF. Added by
/// anyone but the admin to an order on its way, they are its delivery paper and the order then
/// waits for the admin to check it (the server decides).
class OrderPapersScreen extends ConsumerStatefulWidget {
  const OrderPapersScreen({required this.order, super.key});

  final RestockOrder order;

  @override
  ConsumerState<OrderPapersScreen> createState() => _OrderPapersScreenState();
}

class _OrderPapersScreenState extends ConsumerState<OrderPapersScreen> {
  List<String> _photoIds = const [];
  bool _busy = false;

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(restockRepositoryProvider)
          .addDocuments(widget.order.id, _photoIds),
      success: t.papersAdded,
    );
    if (ok && mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.orderAddPapers)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t.orderPapersHint,
            style: context.text.bodyMedium?.copyWith(
              color: context.status.muted,
            ),
          ),
          const Gap(16),
          PhotoSet(
            label: t.photoOfPaper,
            onChanged: (ids, busy) => setState(() {
              _photoIds = ids;
              _busy = busy;
            }),
          ),
          const Gap(8),
          AsyncButton(
            label: t.orderAddPapers,
            icon: LucideIcons.paperclip,
            onPressed: _busy || _photoIds.isEmpty ? null : _send,
          ),
        ],
      ),
    );
  }
}
