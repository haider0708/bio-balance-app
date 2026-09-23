import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../data/repositories/group_repository.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/workspace_scope.dart';
import '../../core/design.dart';
import '../../core/form_draft.dart';
import '../../core/navigation.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class GroupMemberEditor extends StatefulWidget {
  final WorkspaceViewModel workspace;
  final PartnerGroup group;
  final Json? member, invitation;
  const GroupMemberEditor({
    super.key,
    required this.workspace,
    required this.group,
    this.member,
    this.invitation,
  });
  @override
  State<GroupMemberEditor> createState() => _GroupMemberEditorState();
}

class _GroupMemberEditorState extends State<GroupMemberEditor> {
  final email = TextEditingController();
  late final FormDraftController draft;
  String role = 'salesperson', query = '';
  final selected = <String>{};
  bool active = true, ready = false, busy = false, completed = false;
  String? error;
  List<Store> get stores => widget.workspace.state.stores
      .where((s) => s.organizationId == widget.group.id)
      .toList();
  Map<String, String> values() => {
    'email': email.text,
    'role': role,
    'active': '$active',
    'storeIds': jsonEncode(selected.toList()),
  };
  @override
  void initState() {
    super.initState();
    final source = widget.member ?? widget.invitation;
    email.text = source?['email'] ?? '';
    role = source?['role'] ?? source?['kind'] ?? 'salesperson';
    active = source?['active'] != false;
    selected.addAll(List<String>.from(source?['storeIds'] ?? []));
    draft = FormDraftController(
      widget.workspace,
      null,
      'group-member:${widget.group.id}:${source?['id'] ?? 'new'}',
      values(),
    );
    email.addListener(persist);
    unawaited(restore());
  }

  Future<void> restore() async {
    try {
      var saved = await draft.restore();
      String? legacyStoreId;
      // Earlier generic forms attached group drafts to the currently open store.
      // Copy them durably before removing the old entry; never drop entered work.
      final previousStore = widget.workspace.state.store;
      if ((saved == null || saved.isEmpty) && previousStore != null) {
        final legacy = await widget.workspace.repository.draft(
          widget.workspace.user.id,
          previousStore.id,
          draft.key,
        );
        if (legacy != null && legacy.isNotEmpty) {
          final values = legacy['values'] is Map
              ? legacy['values'] as Map
              : legacy;
          saved = {
            for (final e in values.entries)
              if (e.value is String) e.key.toString(): e.value as String,
          };
          legacyStoreId = previousStore.id;
        }
      }
      if (!mounted) return;
      if (saved != null && saved.isNotEmpty) {
        email.text = saved['email'] ?? email.text;
        role = saved['role'] ?? role;
        active = saved['active'] != 'false' && saved['active'] != 'no';
        selected
          ..clear()
          ..addAll(
            saved['storeIds'] != null
                ? List<String>.from(jsonDecode(saved['storeIds']!))
                : [
                    for (final e in saved.entries)
                      if (e.key.startsWith('store:') && e.value == 'yes')
                        e.key.substring(6),
                  ],
          );
        await draft.change(values());
        if (legacyStoreId != null) {
          await widget.workspace.repository.saveDraft(
            widget.workspace.user.id,
            legacyStoreId,
            draft.key,
            {},
          );
        }
      }
      if (mounted) setState(() => ready = true);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }
  }

  void persist() {
    if (!ready || busy) return;
    unawaited(
      draft.change(values()).catchError((Object e) {
        if (mounted) setState(() => error = SessionViewModel.message(e));
      }),
    );
  }

  @override
  void dispose() {
    draft.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: widget.member != null
        ? 'Modifier l’accès'
        : widget.invitation != null
        ? 'Renvoyer l’invitation'
        : 'Inviter dans le groupe',
    action: FilledButton.icon(
      key: const ValueKey('editor.save'),
      onPressed: !ready || busy || completed ? null : save,
      icon: Icon(widget.member == null ? AppIcons.mailOutline : AppIcons.check),
      label: Text(
        completed
            ? 'Enregistré'
            : busy
            ? 'Enregistrement…'
            : widget.member != null
            ? 'Enregistrer l’accès'
            : widget.invitation != null
            ? 'Renvoyer avec cet accès'
            : 'Envoyer l’invitation',
      ),
    ),
    children: [
      SectionTitle(
        widget.group.name,
        subtitle: 'Un compte personnel. Un rôle clair. Les magasins autorisés ci-dessous.',
      ),
      if (error != null) ...[
        Notice(error!, error: true),
        const SizedBox(height: 16),
      ],
      if (!ready) const LinearProgressIndicator(),
      if (!ready && error != null)
        TextButton(onPressed: restore, child: const Text('Réessayer')),
      TextField(
        key: const ValueKey('field.email'),
        controller: email,
        enabled:
            ready &&
            !busy &&
            widget.member == null &&
            widget.invitation == null,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Adresse email'),
      ),
      const SizedBox(height: 24),
      const SectionTitle('Quel rôle lui donner ?'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in const {
            'salesperson': 'Vendeur',
            'responsible': 'Responsable',
          }.entries)
            ChoiceChip(
              label: Text(entry.value),
              selected: role == entry.key,
              onSelected: !ready || busy
                  ? null
                  : (_) {
                      setState(() => role = entry.key);
                      persist();
                    },
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (role == 'responsible')
        const Notice(
          'Accès à tous les magasins de ce groupe, actuels et futurs : équipe, stock, ventes, commandes et récompenses.',
        )
      else ...[
        const Text(
          'Enregistre les ventes et réceptions. Consulte ses points et ses formations.',
        ),
        const SizedBox(height: 20),
        SectionTitle(
          'Magasins autorisés',
          subtitle:
              '${selected.where((id) => stores.any((s) => s.id == id)).length} sélectionné(s) · plusieurs choix possibles',
        ),
        if (stores.length > 5)
          TextField(
            onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              hintText: 'Rechercher un magasin',
              prefixIcon: Icon(AppIcons.search),
            ),
          ),
        for (final store in stores.where(
          (s) => '${s.name} ${s.city}'.toLowerCase().contains(query),
        ))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(store.name),
            subtitle: Text(store.city),
            value: selected.contains(store.id),
            onChanged: !ready || busy
                ? null
                : (v) {
                    setState(() {
                      v == true
                          ? selected.add(store.id)
                          : selected.remove(store.id);
                    });
                    persist();
                  },
          ),
        if (stores.isEmpty)
          const Notice('Créez un magasin avant d’inviter un vendeur.'),
      ],
      if (widget.member != null) ...[
        const SizedBox(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Accès actif'),
          subtitle: const Text('La désactivation conserve tout l’historique.'),
          value: active,
          onChanged: !ready || busy
              ? null
              : (v) {
                  setState(() => active = v);
                  persist();
                },
        ),
      ],
      if (widget.invitation != null) ...[
        const SizedBox(height: 20),
        const Notice(
          'Un nouveau code sera envoyé. L’ancien code sera désactivé ; une seule invitation restera active.',
        ),
      ],
    ],
  );
  Future<void> save() async {
    if (busy || !ready || completed) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final address = email.text.trim().toLowerCase();
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(address)) {
        throw const FormatException('Saisissez une adresse email valide.');
      }
      final ids = role == 'responsible'
          ? <String>[]
          : selected.where((id) => stores.any((s) => s.id == id)).toList();
      if (role == 'salesperson' && active && ids.isEmpty) {
        throw const FormatException(
          'Choisissez au moins un magasin pour ce vendeur.',
        );
      }
      await draft.beginSubmission();
      if (widget.member != null) {
        await GroupRepository(
          widget.workspace.repositoryContext,
          widget.workspace.repository,
          widget.workspace.user.id,
        ).member(widget.group.id, widget.member!['id'], {
          'role': role,
          'active': active,
          'storeIds': ids,
        });
      } else {
        await widget.workspace.teams.invite({
          'email': address,
          'kind': role,
          'organizationId': widget.group.id,
          'storeIds': ids,
          'permissions': role == 'responsible'
              ? ['manage', 'sell', 'receive']
              : ['sell', 'receive'],
        });
      }
      completed = true;
      // An accepted invitation must not be sent again if local cleanup fails.
      try {
        await draft.complete();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Accès enregistré. Le brouillon n’a pas pu être effacé ; vérifiez l’espace disponible.',
              ),
            ),
          );
        }
      }
      if (mounted) completeRoute(context, true);
    } catch (e) {
      draft.submissionFailed();
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
