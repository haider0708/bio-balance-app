import 'package:flutter/material.dart';

import '../features/authentication/session_view_model.dart';
import 'design.dart';

class FieldSpec {
  final String key, label;
  final String initial;
  final bool required, numeric, multiline;
  final Map<String, String>? options;
  const FieldSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.required = true,
    this.numeric = false,
    this.multiline = false,
    this.options,
  });
}

class EditorScreen extends StatefulWidget {
  final String title;
  final String? description;
  final List<FieldSpec> fields;
  final Future<void> Function(Map<String, String>) submit;
  final String submitLabel;
  const EditorScreen({
    super.key,
    required this.title,
    required this.fields,
    required this.submit,
    this.description,
    this.submitLabel = 'Enregistrer',
  });
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final key = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controllers;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    controllers = {
      for (final f in widget.fields)
        f.key: TextEditingController(text: f.initial),
    };
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Content(
      maxWidth: 640,
      children: [
        if (widget.description != null) ...[
          Notice(widget.description!),
          const SizedBox(height: 24),
        ],
        if (error != null) ...[
          Notice(error!, error: true),
          const SizedBox(height: 16),
        ],
        Form(
          key: key,
          child: Column(
            children: widget.fields
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: f.options == null
                        ? TextFormField(
                            controller: controllers[f.key],
                            keyboardType: f.numeric
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                  )
                                : f.multiline
                                ? TextInputType.multiline
                                : TextInputType.text,
                            minLines: f.multiline ? 4 : 1,
                            maxLines: f.multiline ? 12 : 1,
                            decoration: InputDecoration(labelText: f.label),
                            validator: (value) =>
                                f.required && (value?.trim().isEmpty ?? true)
                                ? 'Ce champ est requis.'
                                : null,
                          )
                        : DropdownButtonFormField<String>(
                            initialValue:
                                f.options!.containsKey(controllers[f.key]!.text)
                                ? controllers[f.key]!.text
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: f.options!.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(
                                      e.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                controllers[f.key]!.text = v ?? '',
                            validator: (value) => f.required && value == null
                                ? 'Choisissez une valeur.'
                                : null,
                          ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Enregistrement…' : widget.submitLabel),
        ),
      ],
    ),
  );
  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.submit({
        for (final e in controllers.entries) e.key: e.value.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

Future<bool> openEditor(
  BuildContext context, {
  required String title,
  required List<FieldSpec> fields,
  required Future<void> Function(Map<String, String>) submit,
  String? description,
  String submitLabel = 'Enregistrer',
}) async =>
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          title: title,
          fields: fields,
          submit: submit,
          description: description,
          submitLabel: submitLabel,
        ),
      ),
    ) ??
    false;
int whole(String input, {bool allowZero = false}) {
  final value = int.tryParse(input);
  if (value == null || value < (allowZero ? 0 : 1) || value > 1000000) {
    throw const FormatException('Saisissez un nombre entier d’unités valide.');
  }
  return value;
}

Future<bool> confirmAction(
  BuildContext context,
  String title,
  String message, {
  String label = 'Confirmer',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(label),
          ),
        ],
      ),
    ) ??
    false;
