import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/announcement_repository.dart';
import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/form_draft.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class AnnouncementScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  const AnnouncementScreen({super.key, required this.vm});
  @override
  State<AnnouncementScreen> createState() => _AnnouncementScreenState();
}

class _AnnouncementScreenState extends State<AnnouncementScreen> {
  final title = TextEditingController(), message = TextEditingController();
  late final Store store = widget.vm.state.store!;
  late final repository = AnnouncementRepository(
    widget.vm.repository,
    widget.vm.api,
  );
  late final FormDraftController draft;
  String id = const Uuid().v4(), audience = 'all';
  bool busy = false, loading = true, uncertain = false;
  String? error;
  @override
  void initState() {
    super.initState();
    draft = FormDraftController(widget.vm, store, 'announcement', {});
    title.addListener(persist);
    message.addListener(persist);
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      final saved = await draft.restore() ?? {};
      final pending = await repository.pending(widget.vm.user.id, store);
      if (!mounted) return;
      final values = pending?.isNotEmpty == true ? pending! : saved;
      uncertain = pending?.isNotEmpty == true;
      id = values['id'] ?? id;
      title.text = values['title'] ?? '';
      message.text = values['body'] ?? '';
      audience = values['audience'] ?? 'all';
    } catch (e) {
      if (mounted) error = SessionViewModel.message(e);
    } finally {
      if (mounted) {
        setState(() => loading = false);
        persist();
      }
    }
  }

  Map<String, String> values() => {
    'id': id,
    'title': title.text,
    'body': message.text,
    'audience': audience,
  };
  void persist() {
    if (!loading) {
      unawaited(
        draft.change(values()).catchError((Object e) {
          if (mounted) setState(() => error = SessionViewModel.message(e));
        }),
      );
    }
  }

  @override
  void dispose() {
    draft.dispose();
    title.dispose();
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Annonce à votre équipe')),
    body: Content(
      maxWidth: 640,
      children: [
        StatusChip(store.name, icon: Icons.storefront_outlined),
        const SizedBox(height: 16),
        const Notice(
          'Le brouillon est conservé. Une connexion est nécessaire pour envoyer à votre équipe.',
        ),
        if (uncertain)
          const Notice(
            'La transmission précédente reste à vérifier. Réessayez sans modifier ce message.',
          ),
        if (error != null) Notice(error!, error: true),
        if (loading) const LinearProgressIndicator(),
        const SizedBox(height: 16),
        TextField(
          controller: title,
          enabled: !busy && !loading && !uncertain,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Titre'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: message,
          enabled: !busy && !loading && !uncertain,
          maxLength: 2000,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'Message'),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: ValueKey(audience),
          initialValue: audience,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 'all', child: Text('Toute l’équipe')),
            DropdownMenuItem(
              value: 'salespeople',
              child: Text('Vendeurs uniquement'),
            ),
          ],
          onChanged: busy || loading || uncertain
              ? null
              : (value) {
                  setState(() => audience = value!);
                  persist();
                },
          decoration: const InputDecoration(labelText: 'Destinataires'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy || loading ? null : send,
          child: Text(
            uncertain
                ? 'Vérifier et reprendre l’envoi'
                : 'Vérifier avant d’envoyer',
          ),
        ),
      ],
    ),
  );
  Future<void> send() async {
    if (title.text.trim().length < 2 || message.text.trim().length < 2) {
      setState(() => error = 'Renseignez un titre et un message.');
      return;
    }
    if (!await confirmAction(
      context,
      'Confirmer l’annonce',
      'Magasin : ${store.name}\nDestinataires : ${audience == 'all' ? 'Toute l’équipe' : 'Vendeurs uniquement'}\n\n${title.text}\n\n${message.text}',
      label: 'Envoyer à cette équipe',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      widget.vm.requireAccess(store, 'manage');
      await draft.change(values());
      await repository.send(widget.vm.user.id, store, values());
      await draft.complete();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      var hasPending = true;
      try {
        hasPending =
            (await repository.pending(widget.vm.user.id, store))?.isNotEmpty ==
            true;
      } catch (_) {
        /* Keep the submitted message immutable until storage recovers. */
      }
      if (mounted) {
        setState(() {
          error = SessionViewModel.message(e);
          uncertain = hasPending;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
