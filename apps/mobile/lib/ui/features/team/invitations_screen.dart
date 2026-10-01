import 'package:flutter/material.dart';

import '../../../data/repositories/invitation_repository.dart';
import '../../../domain/models/invitation.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/workspace_scope.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';
import '../stores/stores_screen.dart';
import 'group_member_editor.dart';

class InvitationsViewModel extends ChangeNotifier {
  final InvitationRepository repository;
  final String? groupId;
  List<Invitation> items = const [];
  String? next, error;
  bool loading = false, busy = false, archived = false, closed = false;
  InvitationsViewModel(this.repository, this.groupId);
  Future<void> load({bool more = false}) async {
    if (loading || closed) return;
    loading = true;
    notifyListeners();
    try {
      final page = await repository.list(
        groupId: groupId,
        after: more ? next : null,
        archived: archived,
      );
      if (closed) return;
      items = more
          ? {
              for (final i in [...items, ...page.items]) i.id: i,
            }.values.toList()
          : page.items;
      next = page.next;
      error = null;
    } catch (e) {
      if (!closed) error = SessionViewModel.message(e);
    } finally {
      loading = false;
      if (!closed) notifyListeners();
    }
  }

  Future<bool> act(Invitation item, String action) async {
    if (busy || loading || closed) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await repository.act(item, action);
      await load();
      return true;
    } catch (e) {
      if (!closed) error = SessionViewModel.message(e);
      return false;
    } finally {
      busy = false;
      if (!closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

enum InvitationFilter {
  all('Toutes'),
  pending('En attente'),
  relaunch('À relancer'),
  accepted('Comptes créés');

  final String label;
  const InvitationFilter(this.label);
  bool contains(Invitation item) => switch (this) {
    all => true,
    pending => item.status == 'pending',
    relaunch => ['expired', 'revoked'].contains(item.status),
    accepted => item.status == 'accepted',
  };
}

class InvitationsScreen extends StatefulWidget {
  final WorkspaceViewModel workspace;
  final PartnerGroup? group;
  const InvitationsScreen({super.key, required this.workspace, this.group});
  @override
  State<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  late final model = InvitationsViewModel(
    InvitationRepository(
      widget.workspace.repositoryContext,
      widget.workspace.repository,
      widget.workspace.user.id,
    ),
    widget.group?.id,
  )..load();
  InvitationFilter filter = InvitationFilter.all;
  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Invitations et suivi')),
    body: ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final shown = model.items.where(filter.contains).toList();
        final busy = model.busy || model.loading;
        return Content.builder(
          onRefresh: model.load,
          itemCount: shown.length + (model.next == null ? 0 : 1),
          itemBuilder: (_, index) {
            if (index == shown.length) {
              return TextButton(
                onPressed: model.loading ? null : () => model.load(more: true),
                child: const Text('Charger les invitations suivantes'),
              );
            }
            return InvitationRow(
              item: shown[index],
              stores: widget.workspace.state.stores,
              busy: busy,
              onAction: (action) => act(shown[index], action),
            );
          },
          children: [
            SectionTitle(
              widget.group?.name ?? 'Responsables invités',
              subtitle: widget.group == null
                  ? 'Les invitations envoyées et leur état.'
                  : 'Invitations et accès de votre équipe.',
              // A grossiste has no team: only its own invitation is managed here.
              action: widget.group?.wholesale == true
                  ? null
                  : FilledButton.icon(
                      onPressed: busy ? null : invite,
                      icon: const Icon(AppIcons.personAddAlt),
                      label: const Text('Inviter'),
                    ),
            ),
            FilterBar<InvitationFilter>(
              options: {
                for (final f in InvitationFilter.values)
                  f: f == InvitationFilter.all
                      ? f.label
                      : '${f.label} (${model.items.where(f.contains).length})',
              },
              selected: filter,
              onChanged: (value) => setState(() => filter = value),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Afficher l’historique'),
              subtitle: const Text('Invitations remplacées ou supprimées.'),
              value: model.archived,
              onChanged: busy
                  ? null
                  : (value) {
                      model.archived = value;
                      model.load();
                    },
            ),
            if (model.loading) const LinearProgressIndicator(),
            if (model.error != null)
              Notice(model.error!, error: true, retry: model.load),
            if (!model.loading && model.error == null && shown.isEmpty)
              EmptyState(
                title: model.items.isEmpty
                    ? 'Aucune invitation'
                    : 'Aucune invitation dans cette rubrique',
                description: 'Vos invitations apparaissent ici avec leur état et leur date de validité.',
              ),
          ],
        );
      },
    ),
  );
  Future<void> invite() async {
    if (widget.group == null) {
      await inviteManager(context, widget.workspace);
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GroupMemberEditor(
            workspace: widget.workspace,
            group: widget.group!,
          ),
        ),
      );
    }
    if (mounted) await model.load();
  }

  Future<void> act(Invitation item, String action) async {
    final (title, message, done) = switch (action) {
      'resend' => (
        item.status == 'pending'
            ? 'Renvoyer l’invitation'
            : 'Relancer l’invitation',
        'Un nouveau code est envoyé à ${item.email}. L’ancien code ne fonctionne plus.',
        'Invitation envoyée à ${item.email}.',
      ),
      'revoke' => (
        'Désactiver l’invitation',
        'Le code envoyé à ${item.email} ne fonctionnera plus. Vous pourrez la relancer plus tard.',
        'Invitation désactivée.',
      ),
      _ => (
        'Supprimer l’invitation',
        item.status == 'pending'
            ? 'Le code envoyé à ${item.email} est désactivé et l’invitation disparaît de la liste.'
            : 'L’invitation disparaît de la liste. Aucun compte n’est modifié.',
        'Invitation supprimée.',
      ),
    };
    if (!await confirmAction(context, title, message, label: 'Confirmer') ||
        !mounted) {
      return;
    }
    final success = await model.act(item, action);
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    }
  }
}

/// One invitation, with exactly the actions its state allows. Once the account
/// exists, nothing can be done to it.
class InvitationRow extends StatelessWidget {
  final Invitation item;
  final List<Store> stores;
  final bool busy;
  final ValueChanged<String> onAction;
  const InvitationRow({
    super.key,
    required this.item,
    required this.stores,
    required this.busy,
    required this.onAction,
  });
  @override
  Widget build(BuildContext context) {
    final names = stores
        .where((s) => item.storeIds.contains(s.id))
        .map((s) => s.name)
        .join(', ');
    return CompactRow(
      title: item.email,
      subtitle: [
        item.roleLabel,
        if (names.isNotEmpty) names,
        if (item.dateLabel.isNotEmpty) item.dateLabel,
      ].join('\n'),
      icon: item.locked ? AppIcons.checkCircleOutline : AppIcons.mailOutline,
      tone: switch (item.status) {
        'accepted' => AppTone.success,
        'expired' => AppTone.warning,
        'revoked' => AppTone.danger,
        _ => AppTone.info,
      },
      footer: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusChip(
            item.statusLabel,
            tone: switch (item.status) {
              'accepted' => AppTone.success,
              'expired' => AppTone.warning,
              'revoked' => AppTone.danger,
              _ => AppTone.info,
            },
          ),
          if (item.canResend)
            FilledButton.tonal(
              onPressed: busy ? null : () => onAction('resend'),
              child: Text(item.status == 'pending' ? 'Renvoyer' : 'Relancer'),
            ),
          if (item.canRevoke)
            TextButton(
              onPressed: busy ? null : () => onAction('revoke'),
              child: const Text('Désactiver'),
            ),
          if (item.canRemove && item.status != 'replaced')
            TextButton(
              onPressed: busy ? null : () => onAction('archive'),
              child: const Text('Supprimer'),
            ),
        ],
      ),
    );
  }
}
