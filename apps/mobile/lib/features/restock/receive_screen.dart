import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/photo_set.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../l10n/app_localizations.dart';
import 'restock_models.dart';
import 'restock_repository.dart';

/// Confirm a delivery with its signed paper (photos or a PDF) and a note. The admin enters the
/// quantities when approving; an admin receiving goods at a grossiste enters them here and the
/// stock is updated at once.
class ReceiveScreen extends ConsumerStatefulWidget {
  const ReceiveScreen({required this.order, super.key});

  final RestockOrder order;

  @override
  ConsumerState<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends ConsumerState<ReceiveScreen> {
  late final QuantityController _quantities = QuantityController([
    for (final l in widget.order.lines.where((l) => (l.shipped ?? 0) > 0))
      QuantityItem(
        productId: l.productId,
        name: l.name,
        family: l.family,
        quantity: l.shipped ?? 0,
      ),
  ]);
  final _note = TextEditingController();
  List<String> _photoIds = const [];
  bool _photosBusy = false;

  @override
  void dispose() {
    _quantities.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(restockRepositoryProvider)
          .receive(
            widget.order.id,
            photoIds: _photoIds,
            lines: _admin ? _quantities.lines() : null,
            note: _note.text.trim(),
          ),
      success: t.deliverySent,
    );
    if (ok && mounted) context.pop(true);
  }

  bool get _admin => ref.read(meProvider).role == Role.admin;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final admin = ref.watch(meProvider).role == Role.admin;
    return Scaffold(
      appBar: AppBar(title: Text(t.confirmDelivery)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            admin ? t.receiveHintAdmin : t.receiveHint,
            style: context.text.bodyMedium?.copyWith(
              color: context.status.muted,
            ),
          ),
          const Gap(16),
          PhotoSet(
            label: t.photoOfPaper,
            onChanged: (ids, busy) => setState(() {
              _photoIds = ids;
              _photosBusy = busy;
            }),
          ),
          if (admin) ...[
            SectionHeader(t.quantitiesReceived),
            QuantityEditor(
              controller: _quantities,
              allowAdd: false,
              allowRemove: false,
            ),
          ] else ...[
            // What should be on the paper, to compare with it.
            SectionHeader(t.whatWasSent),
            AppCard(
              child: Column(
                children: [
                  for (final l in widget.order.lines.where(
                    (l) => (l.shipped ?? 0) > 0,
                  ))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        spacing: 12,
                        children: [
                          Expanded(child: Text(l.name)),
                          Text('${l.shipped}', style: context.text.titleSmall),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const Gap(16),
          TextField(
            controller: _note,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(labelText: '${t.note} (${t.optional})'),
          ),
          const Gap(8),
          AsyncButton(
            label: admin ? t.recordDeliverySave : t.sendToAdmin,
            icon: admin ? LucideIcons.check : LucideIcons.send,
            onPressed: _photoIds.isEmpty || _photosBusy ? null : _send,
          ),
          if (_photoIds.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                t.photoRequiredHint,
                textAlign: TextAlign.center,
                style: context.text.bodySmall?.copyWith(
                  color: context.status.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
