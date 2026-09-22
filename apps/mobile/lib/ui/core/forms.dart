import 'navigation.dart';

import 'dart:async';
import 'dart:convert';

import 'package:provider/provider.dart';

import '../features/workspace/workspace_view_model.dart';
import 'form_draft.dart';
import '../features/media/image_input.dart';
import '../../domain/models/models.dart';

import 'package:flutter/material.dart';

import '../features/authentication/session_view_model.dart';
import 'design.dart';
import 'option_field.dart';

class FieldSpec {
  final String key, label;
  final String initial;
  final bool required, numeric, multiline;
  final Map<String, String>? options;
  final String? imagePurpose;
  const FieldSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.required = true,
    this.numeric = false,
    this.multiline = false,
    this.options,
    this.imagePurpose,
  });
}

class EditorScreen extends StatefulWidget {
  final String title;
  final String? description;
  final List<FieldSpec> fields;
  final Future<void> Function(Map<String, String>) submit;
  final String submitLabel;
  final WorkspaceViewModel? workspace;
  const EditorScreen({
    super.key,
    required this.title,
    required this.fields,
    required this.submit,
    this.description,
    this.workspace,
    this.submitLabel = 'Enregistrer',
  });
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final key = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controllers;
  bool busy = false, mediaBusy = false;
  String? error;
  FormDraftController? draft;
  bool restoringDraft = false;
  Store? draftStore;
  @override
  void initState() {
    super.initState();
    controllers = {
      for (final f in widget.fields)
        f.key: TextEditingController(text: f.initial),
    };
    final workspace = widget.workspace;
    final store = workspace?.state.store;
    draftStore = store;
    if (workspace != null) {
      draft = FormDraftController(
        workspace,
        store,
        'editor:${jsonEncode([
          widget.title,
          widget.fields.map((f) => [f.key, f.initial]).toList(),
        ])}',
        {for (final entry in controllers.entries) entry.key: entry.value.text},
      );
      for (final controller in controllers.values) {
        controller.addListener(persist);
      }
      unawaited(restoreDraft());
    }
  }

  Future<void> restoreDraft() async {
    try {
      final restored = await draft?.restore();
      if (!mounted || restored == null) return;
      restoringDraft = true;
      for (final entry in restored.entries) {
        controllers[entry.key]?.text = entry.value;
      }
      restoringDraft = false;
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }
  }

  void persist() {
    if (restoringDraft || draft == null) return;
    unawaited(
      draft!
          .change({for (final e in controllers.entries) e.key: e.value.text})
          .catchError((Object e) {
            if (mounted) {
              setState(
                () => error = 'Le brouillon n’a pas pu être enregistré. Vérifiez l’espace disponible.',
              );
            }
          }),
    );
  }

  @override
  void dispose() {
    draft?.dispose();
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
          Text(
            widget.description!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
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
                    padding: const EdgeInsets.only(bottom: 16),
                    child: f.imagePurpose != null && widget.workspace != null
                        ? ImageInput(
                            vm: widget.workspace!,
                            store: f.imagePurpose == 'catalog'
                                ? null
                                : draftStore,
                            purpose: f.imagePurpose!,
                            label: f.label,
                            controller: controllers[f.key]!,
                            enabled: !busy,
                            onBusyChanged: (value) {
                              if (mounted) {
                                setState(() => mediaBusy = value);
                              }
                            },
                          )
                        : f.options == null
                        ? TextFormField(
                            key: ValueKey('field.${f.key}'),
                            controller: controllers[f.key],
                            enabled: !busy && !mediaBusy,
                            textInputAction: f.multiline
                                ? TextInputAction.newline
                                : widget.fields.last.key == f.key
                                ? TextInputAction.done
                                : TextInputAction.next,
                            onFieldSubmitted: (_) {
                              if (widget.fields.last.key == f.key) {
                                save();
                              }
                            },
                            keyboardType: f.numeric
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                  )
                                : f.multiline
                                ? TextInputType.multiline
                                : f.key.toLowerCase().contains('email')
                                ? TextInputType.emailAddress
                                : f.key.toLowerCase().contains('phone')
                                ? TextInputType.phone
                                : TextInputType.text,
                            minLines: f.multiline ? 4 : 1,
                            maxLines: f.multiline ? 12 : 1,
                            decoration: InputDecoration(labelText: f.label),
                            validator: (value) =>
                                f.required && (value?.trim().isEmpty ?? true)
                                ? 'Ce champ est requis.'
                                : null,
                          )
                        : OptionField(
                            key: ValueKey('field.${f.key}'),
                            label: f.label,
                            options: f.options!,
                            controller: controllers[f.key]!,
                            required: f.required,
                            enabled: !busy && !mediaBusy,
                          ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    ),
    bottomNavigationBar: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: BottomAction(
        child: FilledButton(
          key: const ValueKey('editor.save'),
          onPressed: busy || mediaBusy ? null : save,
          child: Text(busy ? 'Enregistrement…' : widget.submitLabel),
        ),
      ),
    ),
  );
  Future<void> save() async {
    if (busy || mediaBusy) return;
    final invalid = key.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      await Scrollable.ensureVisible(
        invalid.first.context,
        alignment: .1,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 120),
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.submit({
        for (final e in controllers.entries) e.key: e.value.text.trim(),
      });
      await draft?.complete();
      if (mounted) completeRoute(context, true);
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
          workspace: context.read<WorkspaceViewModel?>(),
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
      useRootNavigator: false,
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
