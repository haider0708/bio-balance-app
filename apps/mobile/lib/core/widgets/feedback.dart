import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'async_body.dart';
import 'components.dart';

void showMessage(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? context.status.danger : null,
        duration: Duration(seconds: error ? 5 : 3),
      ),
    );
}

void showError(BuildContext context, Object error) =>
    showMessage(context, errorMessage(context, error), error: true);

/// Run an action; show a message on success or a readable error on failure.
/// Returns true when it worked.
Future<bool> perform(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) showMessage(context, success);
    return true;
  } catch (error) {
    if (context.mounted) showError(context, error);
    return false;
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final t = AppLocalizations.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.cancel)),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive ? TextButton.styleFrom(foregroundColor: context.status.danger) : null,
          child: Text(confirmLabel ?? t.confirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Ask for a short written reason (a rejection, a correction).
Future<String?> askNote(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? hint,
  bool required = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _NoteSheet(title: title, confirmLabel: confirmLabel, hint: hint, required: required),
  );
}

class _NoteSheet extends StatefulWidget {
  const _NoteSheet({required this.title, required this.confirmLabel, required this.required, this.hint});

  final String title;
  final String confirmLabel;
  final String? hint;
  final bool required;

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = !widget.required || _controller.text.trim().length >= 2;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: context.text.titleLarge),
          const Gap(16),
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: widget.hint),
            onChanged: (_) => setState(() {}),
          ),
          const Gap(12),
          FilledButton(
            onPressed: valid ? () => Navigator.pop(context, _controller.text.trim()) : null,
            child: Text(widget.confirmLabel),
          ),
        ],
      ),
    );
  }
}
