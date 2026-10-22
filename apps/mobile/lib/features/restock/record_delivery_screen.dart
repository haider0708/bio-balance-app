import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/photo_set.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../l10n/app_localizations.dart';
import '../network/network_repository.dart';
import '../stock/stock_repository.dart';
import 'restock_repository.dart';

/// The admin restocks a grossiste herself: she counts what BioBalance delivered and photographs it;
/// the goods are added to its stock as soon as she saves.
class RecordDeliveryScreen extends ConsumerStatefulWidget {
  const RecordDeliveryScreen({
    required this.depotId,
    required this.depotName,
    super.key,
  });

  final String depotId;
  final String depotName;

  @override
  ConsumerState<RecordDeliveryScreen> createState() =>
      _RecordDeliveryScreenState();
}

class _RecordDeliveryScreenState extends ConsumerState<RecordDeliveryScreen> {
  final _quantities = QuantityController();
  final _note = TextEditingController();
  List<String> _photoIds = const [];
  bool _photosBusy = false;

  @override
  void dispose() {
    _quantities.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(restockRepositoryProvider)
          .create(
            destId: widget.depotId,
            note: _note.text.trim(),
            photoIds: _photoIds,
            lines: _quantities.lines(skipZero: true),
          ),
      success: t.deliveryRecorded,
    );
    if (ok && mounted) {
      ref
        ..invalidate(restocksProvider)
        ..invalidate(stockLevelsProvider(widget.depotId))
        ..invalidate(depotsProvider);
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.recordDeliveryTitle(widget.depotName))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t.recordDeliveryHint,
            style: context.text.bodyMedium?.copyWith(
              color: context.status.muted,
            ),
          ),
          const Gap(16),
          PhotoSet(
            label: t.photoOfGoods,
            onChanged: (ids, busy) => setState(() {
              _photoIds = ids;
              _photosBusy = busy;
            }),
          ),
          SectionHeader(t.quantitiesReceived),
          QuantityEditor(
            controller: _quantities,
            addLabel: t.addProduct,
            allowPaste: true,
          ),
          const Gap(16),
          TextField(
            controller: _note,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(labelText: '${t.note} (${t.optional})'),
          ),
          const Gap(8),
          ListenableBuilder(
            listenable: _quantities,
            builder: (context, _) => AsyncButton(
              label: t.recordDeliverySave,
              icon: LucideIcons.check,
              onPressed:
                  _photoIds.isEmpty || _photosBusy || _quantities.total == 0
                  ? null
                  : _save,
            ),
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
