import '../../core/navigation.dart';

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
  bool busy = false,
      loading = true,
      uncertain = false,
      restored = false,
      confirming = false;
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
    setState(() {
      loading = true;
      error = null;
    });
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
      restored = true;
    } catch (e) {
      if (mounted) error = SessionViewModel.message(e);
    } finally {
      if (mounted) {
        setState(() => loading = false);
        if (restored) persist();
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
    if (!loading && restored) {
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
        StatusChip(store.name, icon: AppIcons.storefrontOutlined),
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
        if (!loading && !restored)
          TextButton(
            onPressed: restore,
            child: const Text('Réessayer de récupérer le brouillon'),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: title,
          enabled: restored && !busy && !loading && !uncertain,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Titre'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: message,
          enabled: restored && !busy && !loading && !uncertain,
          maxLength: 2000,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(labelText: 'Message'),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          icon: const Icon(AppIcons.keyboardArrowDown),
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
          onChanged: !restored || busy || loading || uncertain
              ? null
              : (value) {
                  setState(() => audience = value!);
                  persist();
                },
          decoration: const InputDecoration(labelText: 'Destinataires'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: !restored || busy || confirming || loading ? null : send,
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
    if (!restored || busy || confirming || draft.completed) return;
    if (title.text.trim().length < 2 || message.text.trim().length < 2) {
      setState(() => error = 'Renseignez un titre et un message.');
      return;
    }
    setState(() => confirming = true);
    final confirmed = await confirmAction(
      context,
      'Confirmer l’annonce',
      'Magasin : ${store.name}\nDestinataires : ${audience == 'all' ? 'Toute l’équipe' : 'Vendeurs uniquement'}\n\n${title.text}\n\n${message.text}',
      label: 'Envoyer à cette équipe',
    );
    if (!mounted) return;
    setState(() => confirming = false);
    if (!confirmed) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      widget.vm.requireAccess(store, 'manage');
      await draft.change(values());
      await repository.send(widget.vm.user.id, store, values());
      try {
        await draft.complete();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Annonce envoyée. Le brouillon sera à nettoyer après récupération du stockage.',
              ),
            ),
          );
        }
      }
      if (mounted) completeRoute(context);
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
