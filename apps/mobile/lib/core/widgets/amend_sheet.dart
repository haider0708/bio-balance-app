import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'components.dart';
import 'quantity_editor.dart';
import '../layout/layout.dart';

/// A bottom sheet to correct quantities before deciding (an approval, an order). Returns the lines.
Future<List<Map<String, Object>>?> amendQuantities(
  BuildContext context, {
  required String title,
  required List<QuantityItem> items,
  String? hint,
  bool allowAdd = false,
  String? confirmLabel,
}) {
  return showModalBottomSheet<List<Map<String, Object>>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AmendSheet(
      title: title,
      hint: hint,
      items: items,
      allowAdd: allowAdd,
      confirmLabel: confirmLabel,
    ),
  );
}

class _AmendSheet extends StatefulWidget {
  const _AmendSheet({
    required this.title,
    required this.items,
    required this.allowAdd,
    this.hint,
    this.confirmLabel,
  });

  final String title;
  final String? hint;
  final List<QuantityItem> items;
  final bool allowAdd;
  final String? confirmLabel;

  @override
  State<_AmendSheet> createState() => _AmendSheetState();
}

/// The sheet owns the quantities it edits, so they live as long as it is drawn, including while it closes.
class _AmendSheetState extends State<_AmendSheet> {
  late final controller = QuantityController(widget.items);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
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
                Text(widget.title, style: context.text.titleLarge),
                if (widget.hint != null) ...[
                  const Gap(4),
                  Text(
                    widget.hint!,
                    style: context.text.bodyMedium?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: QuantityEditor(
                controller: controller,
                allowAdd: widget.allowAdd,
                allowRemove: widget.allowAdd,
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => FilledButton(
                  onPressed: controller.isEmpty
                      ? null
                      : () => Navigator.pop(context, controller.lines()),
                  child: Text(widget.confirmLabel ?? t.confirm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
