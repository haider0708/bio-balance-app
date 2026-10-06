import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'components.dart';
import 'quantity_editor.dart';

/// A bottom sheet to correct quantities before deciding (an approval, an order). Returns the lines.
Future<List<Map<String, Object>>?> amendQuantities(
  BuildContext context, {
  required String title,
  required List<QuantityItem> items,
  String? hint,
  bool allowAdd = false,
  String? confirmLabel,
}) {
  final controller = QuantityController(items);
  return showModalBottomSheet<List<Map<String, Object>>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _AmendSheet(
      title: title,
      hint: hint,
      controller: controller,
      allowAdd: allowAdd,
      confirmLabel: confirmLabel,
    ),
  ).whenComplete(controller.dispose);
}

class _AmendSheet extends StatelessWidget {
  const _AmendSheet({
    required this.title,
    required this.controller,
    required this.allowAdd,
    this.hint,
    this.confirmLabel,
  });

  final String title;
  final String? hint;
  final QuantityController controller;
  final bool allowAdd;
  final String? confirmLabel;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.text.titleLarge),
                if (hint != null) ...[
                  const Gap(4),
                  Text(
                    hint!,
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
                allowAdd: allowAdd,
                allowRemove: allowAdd,
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
                  child: Text(confirmLabel ?? t.confirm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
