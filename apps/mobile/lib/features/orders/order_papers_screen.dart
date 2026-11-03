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

/// Attach the papers of an order (invoice, delivery note) or, with [delivered], say that it reached
/// the place, with the paper that proves it. The place still confirms and the admin approves.
class OrderPapersScreen extends ConsumerStatefulWidget {
  const OrderPapersScreen({
    required this.order,
    this.delivered = false,
    super.key,
  });

  final RestockOrder order;
  final bool delivered;

  @override
  ConsumerState<OrderPapersScreen> createState() => _OrderPapersScreenState();
}

class _OrderPapersScreenState extends ConsumerState<OrderPapersScreen> {
  final _note = TextEditingController();
  List<String> _photoIds = const [];
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    final repo = ref.read(restockRepositoryProvider);
    final ok = await perform(
      context,
      () => widget.delivered
          ? repo.delivered(
              widget.order.id,
              photoIds: _photoIds,
              note: _note.text.trim(),
            )
          : repo.addDocuments(widget.order.id, _photoIds),
      success: widget.delivered ? t.orderDeliveredDone : t.papersAdded,
    );
    if (ok && mounted) context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final delivered = widget.delivered;
    // Saying "delivered" needs no paper; adding papers needs at least one.
    final ready = !_busy && (delivered || _photoIds.isNotEmpty);
    return Scaffold(
      appBar: AppBar(
        title: Text(delivered ? t.orderMarkDelivered : t.orderAddPapers),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            delivered ? t.orderDeliveredHint : t.orderPapersHint,
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
          if (delivered) ...[
            const Gap(16),
            TextField(
              controller: _note,
              maxLength: 300,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '${t.note} (${t.optional})',
              ),
            ),
          ],
          const Gap(8),
          AsyncButton(
            label: delivered ? t.orderMarkDelivered : t.orderAddPapers,
            icon: delivered ? LucideIcons.circleCheck : LucideIcons.paperclip,
            onPressed: ready ? _send : null,
          ),
        ],
      ),
    );
  }
}
