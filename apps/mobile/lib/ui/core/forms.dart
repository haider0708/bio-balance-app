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

  /// Renders a short list of options as chips instead of a searchable sheet.
  /// Suitable when the number of choices is known to stay small.
  final bool choice;
  final String? section;
  final String? hint;
  final String? imagePurpose;
  final String? imageGroupId;
  const FieldSpec(
    this.key,
    this.label, {
    this.initial = '',
    this.required = true,
    this.numeric = false,
    this.multiline = false,
    this.options,
    this.choice = false,
    this.section,
    this.hint,
    this.imagePurpose,
    this.imageGroupId,
  }) : assert(!choice || options != null, 'A choice field needs its options.');
}

class EditorScreen extends StatefulWidget {
  final String title;
  final String? description;
  final List<FieldSpec> fields;
  final Future<void> Function(Map<String, String>)? submit;
  final Future<void> Function(Map<String, String>, String?)? submitWithDraft;
  final String? draftKey;
  final String submitLabel;
  final WorkspaceViewModel? workspace;
  const EditorScreen({
    super.key,
    required this.title,
    required this.fields,
    this.submit,
    this.submitWithDraft,
    this.draftKey,
    this.description,
    this.workspace,
    this.submitLabel = 'Enregistrer',
  }) : assert((submit == null) != (submitWithDraft == null));
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final key = GlobalKey<FormState>();
  late final Map<String, TextEditingController> controllers;
  bool busy = false, mediaBusy = false, completed = false;
  String? error;
  FormDraftController? draft;
  bool restoringDraft = false, draftReady = true;
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
      draftReady = false;
      draft = FormDraftController(
        workspace,
        store,
        widget.draftKey ??
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
    setState(() {
      restoringDraft = true;
      error = null;
    });
    try {
      final restored = await draft?.restore();
      if (!mounted) return;
      for (final entry in (restored ?? <String, String>{}).entries) {
        controllers[entry.key]?.text = entry.value;
      }
      draftReady = true;
    } catch (e) {
      if (mounted) error = SessionViewModel.message(e);
    } finally {
      if (mounted) setState(() => restoringDraft = false);
    }
  }

  void persist() {
    if (!draftReady || restoringDraft || draft == null) return;
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
  Widget build(BuildContext context) => FormPage(
    title: widget.title,
    maxWidth: 640,
    action: FilledButton(
      key: const ValueKey('editor.save'),
      onPressed: !draftReady || busy || mediaBusy || completed ? null : save,
      child: Text(
        completed
            ? 'Enregistré'
            : busy
            ? 'Enregistrement…'
            : widget.submitLabel,
      ),
    ),
    children: [
      if (widget.description != null) ...[
        Text(widget.description!, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
      ],
      if (error != null) ...[
        Notice(error!, error: true),
        const SizedBox(height: 16),
      ],
      if (restoringDraft) const LinearProgressIndicator(),
      if (!draftReady && !restoringDraft)
        TextButton.icon(
          onPressed: restoreDraft,
          icon: const Icon(AppIcons.refresh),
          label: const Text('Réessayer de récupérer le brouillon'),
        ),
      Form(
        key: key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: widget.fields
              .expand<Widget>(
                (f) => [
                  if (f.section != null) FormSectionHeading(f.section!),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: f.imagePurpose != null && widget.workspace != null
                        ? ImageInput(
                            vm: widget.workspace!,
                            store: ['catalog', 'group'].contains(f.imagePurpose)
                                ? null
                                : draftStore,
                            purpose: f.imagePurpose!,
                            groupId: f.imageGroupId,
                            label: f.label,
                            controller: controllers[f.key]!,
                            enabled: draftReady && !busy && !completed,
                            onBusyChanged: (value) {
                              if (mounted) {
                                setState(() => mediaBusy = value);
                              }
                            },
                          )
                        : f.choice
                        ? _ChoiceChips(
                            key: ValueKey('field.${f.key}'),
                            label: f.label,
                            hint: f.hint,
                            options: f.options!,
                            controller: controllers[f.key]!,
                            required: f.required,
                            enabled:
                                draftReady && !busy && !mediaBusy && !completed,
                          )
                        : f.options == null
                        ? TextFormField(
                            key: ValueKey('field.${f.key}'),
                            controller: controllers[f.key],
                            enabled:
                                draftReady && !busy && !mediaBusy && !completed,
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
                            maxLines: f.multiline ? null : 1,
                            decoration: InputDecoration(
                              labelText: f.label,
                              alignLabelWithHint: f.multiline,
                              helperText:
                                  f.hint ?? (f.required ? null : 'Facultatif'),
                              helperMaxLines: 3,
                            ),
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
                            enabled:
                                draftReady && !busy && !mediaBusy && !completed,
                          ),
                  ),
                ],
              )
              .toList(),
        ),
      ),
    ],
  );
  Future<void> save() async {
    if (!draftReady || busy || mediaBusy || completed) return;
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
      await draft?.beginSubmission();
      final values = {
        for (final e in controllers.entries) e.key: e.value.text.trim(),
      };
      if (widget.submitWithDraft != null) {
        await widget.submitWithDraft!(values, draft?.key);
      } else {
        await widget.submit!(values);
      }
      completed = true;
      // Submission has succeeded. Draft cleanup cannot turn it into a failed
      // operation and offer a second submission of the same business action.
      try {
        await draft?.complete();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Opération enregistrée. Le brouillon n’a pas pu être effacé ; vérifiez l’espace disponible.',
              ),
            ),
          );
        }
      }
      if (mounted) completeRoute(context, true);
    } catch (e) {
      draft?.submissionFailed();
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
  Future<void> Function(Map<String, String>)? submit,
  Future<void> Function(Map<String, String>, String?)? submitWithDraft,
  String? draftKey,
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
          submitWithDraft: submitWithDraft,
          draftKey: draftKey,
          description: description,
          submitLabel: submitLabel,
        ),
      ),
    ) ??
    false;

/// A small closed set of options shown as chips. The selection lives in the
/// form's own controller, so a saved draft restores the choice without a
/// separate value that could drift.
class _ChoiceChips extends StatefulWidget {
  final String label;
  final String? hint;
  final Map<String, String> options;
  final TextEditingController controller;
  final bool required, enabled;
  const _ChoiceChips({
    super.key,
    required this.label,
    required this.options,
    required this.controller,
    this.hint,
    this.required = true,
    this.enabled = true,
  });

  @override
  State<_ChoiceChips> createState() => _ChoiceChipsState();
}

class _ChoiceChipsState extends State<_ChoiceChips> {
  final field = GlobalKey<FormFieldState<String>>();
  String? get selected => widget.options.containsKey(widget.controller.text)
      ? widget.controller.text
      : null;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
  }

  @override
  void didUpdateWidget(covariant _ChoiceChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(changed);
      widget.controller.addListener(changed);
    }
  }

  void changed() {
    field.currentState?.didChange(selected);
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormField<String>(
    key: field,
    initialValue: selected,
    validator: (_) =>
        widget.required && selected == null ? 'Choisissez une valeur.' : null,
    builder: (state) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: widget.enabled ? ink : muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (widget.hint != null) ...[
          const SizedBox(height: 2),
          Text(widget.hint!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in widget.options.entries)
              ChoiceChip(
                key: ValueKey('field.${widget.label}.${option.key}'),
                label: Text(option.value),
                selected: option.key == selected,
                onSelected: !widget.enabled
                    ? null
                    : (value) =>
                          widget.controller.text = value ? option.key : '',
              ),
          ],
        ),
        if (state.errorText != null) ...[
          const SizedBox(height: 6),
          Text(
            state.errorText!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    ),
  );
}

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
