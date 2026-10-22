import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../api/api_client.dart';
import '../api/json.dart';
import '../auth/session.dart';
import '../layout/layout.dart';
import '../theme/app_theme.dart';
import 'components.dart';
import 'feedback.dart';
import 'quantity_editor.dart';

/// A product found for a pasted line.
class PastedProduct {
  const PastedProduct({
    required this.id,
    required this.name,
    required this.family,
    this.imageId,
  });

  factory PastedProduct.fromJson(Json j) => PastedProduct(
    id: j.str('id'),
    name: j.str('name'),
    family: j.str('family'),
    imageId: j.strOrNull('imageId'),
  );

  final String id;
  final String name;
  final String family;
  final String? imageId;
}

/// One pasted line and what the server found for it: MATCHED, UNSURE (candidates) or MISSING.
class PastedLine {
  PastedLine({
    required this.raw,
    required this.quantity,
    required this.status,
    this.product,
    this.candidates = const [],
  }) : chosen = product;

  factory PastedLine.fromJson(Json j) => PastedLine(
    raw: j.str('raw'),
    quantity: j.integerOrNull('quantity') ?? 1,
    status: j.str('status'),
    product: j.objOrNull('product') == null
        ? null
        : PastedProduct.fromJson(j.obj('product')),
    candidates: [
      for (final c in (j['candidates'] as List? ?? const []))
        PastedProduct.fromJson(c as Json),
    ],
  );

  final String raw;
  final int quantity;
  final String status;
  final PastedProduct? product;
  final List<PastedProduct> candidates;

  /// The product that will be added: the sure match, or the one picked among the candidates.
  PastedProduct? chosen;
}

/// Asks the server to match a pasted list to the catalogue.
Future<List<PastedLine>> matchPastedList(ApiClient client, String text) async {
  final data = await client.post('/v1/products/match', {'text': text}) as Json;
  return data.list('lines').map(PastedLine.fromJson).toList();
}

/// Opens the "paste a list" sheet and puts what was understood into [controller]: a product already
/// in the list takes the pasted quantity, the others are added.
Future<void> pasteIntoList(
  BuildContext context,
  QuantityController controller,
) async {
  final lines = await showModalBottomSheet<List<PastedLine>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => const _PasteSheet(),
  );
  if (lines == null) return;
  for (final l in lines) {
    final p = l.chosen;
    if (p == null) continue;
    if (controller.contains(p.id)) {
      controller.setQuantity(p.id, l.quantity);
    } else {
      controller.addItem(
        QuantityItem(
          productId: p.id,
          name: p.name,
          family: p.family,
          imageId: p.imageId,
          quantity: l.quantity,
        ),
      );
    }
  }
}

class _PasteSheet extends ConsumerStatefulWidget {
  const _PasteSheet();

  @override
  ConsumerState<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends ConsumerState<_PasteSheet> {
  final _text = TextEditingController();
  List<PastedLine>? _lines;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      _text.text = data!.text!;
      setState(() => _lines = null);
    }
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final lines = await matchPastedList(
        ref.read(apiClientProvider),
        _text.text,
      );
      if (mounted) setState(() => _lines = lines);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final lines = _lines;
    final matched = lines?.where((l) => l.status == 'MATCHED').length ?? 0;
    final unsure = lines?.where((l) => l.status == 'UNSURE').length ?? 0;
    final missing = lines?.where((l) => l.status == 'MISSING').length ?? 0;
    final ready = lines?.where((l) => l.chosen != null).length ?? 0;
    return Padding(
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.pasteListTitle, style: context.text.titleMedium),
                const Gap(4),
                Text(
                  t.pasteListHint,
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              children: [
                TextField(
                  controller: _text,
                  minLines: 4,
                  maxLines: 8,
                  onChanged: (_) => setState(() => _lines = null),
                  decoration: InputDecoration(
                    hintText: '26 serum discoloration\n8697711600852  …  8',
                    suffixIcon: IconButton(
                      tooltip: t.pasteFromClipboard,
                      icon: const Icon(LucideIcons.clipboardPaste),
                      onPressed: _paste,
                    ),
                  ),
                ),
                if (lines != null) ...[
                  const Gap(12),
                  Text(
                    t.pasteSummary(matched, unsure, missing),
                    style: context.text.labelLarge,
                  ),
                  const Gap(8),
                  for (final l in lines) ...[
                    _LineTile(line: l, onChanged: () => setState(() {})),
                    const Gap(8),
                  ],
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: lines == null
                ? FilledButton(
                    onPressed: _busy || _text.text.trim().isEmpty
                        ? null
                        : _check,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(t.pasteCheck),
                  )
                : FilledButton(
                    onPressed: ready == 0
                        ? null
                        : () => Navigator.pop(context, lines),
                    child: Text(t.pasteAdd(ready)),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line, required this.onChanged});

  final PastedLine line;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final sure = line.status == 'MATCHED';
    final tone = sure
        ? context.status.success
        : line.chosen != null
        ? context.status.info
        : line.status == 'UNSURE'
        ? context.status.warning
        : context.status.danger;
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sure || line.chosen != null
                    ? LucideIcons.check
                    : LucideIcons.triangleAlert,
                size: 18,
                color: tone,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  line.chosen?.name ?? line.raw,
                  style: context.text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('× ${line.quantity}', style: context.text.titleSmall),
            ],
          ),
          if (line.chosen != null && line.chosen!.name != line.raw)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 26),
              child: Text(
                line.raw,
                style: context.text.bodySmall?.copyWith(
                  color: context.status.muted,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (line.status == 'UNSURE') ...[
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in line.candidates)
                  ChoiceChip(
                    label: Text(c.name, overflow: TextOverflow.ellipsis),
                    selected: line.chosen?.id == c.id,
                    onSelected: (on) {
                      line.chosen = on ? c : null;
                      onChanged();
                    },
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                t.pasteChoose,
                style: context.text.bodySmall?.copyWith(
                  color: context.status.muted,
                ),
              ),
            ),
          ],
          if (line.status == 'MISSING')
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 26),
              child: Text(
                t.pasteNotFound,
                style: context.text.bodySmall?.copyWith(
                  color: context.status.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
