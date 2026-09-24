import 'package:flutter/material.dart';

import '../../../data/repositories/invitation_repository.dart';
import '../../../domain/models/invitation.dart';
import '../../../domain/models/tunis_dates.dart';
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
      builder: (context, _) => Content.builder(
        itemCount: model.items.length + (model.next == null ? 0 : 1),
        itemBuilder: (_, index) {
          if (index == model.items.length) {
            return TextButton(
              onPressed: model.loading ? null : () => model.load(more: true),
              child: const Text('Charger les invitations suivantes'),
            );
          }
          final item = model.items[index];
          return CompactRow(
            title: item.email,
            subtitle:
                '${item.roleLabel}\n${item.status == 'accepted' ? 'Activée le ${TunisDates.timestampLabel(item.acceptedAt ?? item.expiresAt)}' : 'Validité : ${TunisDates.timestampLabel(item.expiresAt)}'}',
            icon: AppIcons.mailOutline,
            footer: StatusChip(
              item.statusLabel,
              tone: switch (item.status) {
                'accepted' => AppTone.success,
                'pending' => AppTone.info,
                'expired' => AppTone.warning,
                'revoked' => AppTone.danger,
                _ => AppTone.info,
              },
              icon: item.status == 'accepted'
                  ? AppIcons.checkCircleOutline
                  : item.status == 'pending'
                  ? AppIcons.mailOutline
                  : AppIcons.infoOutline,
            ),
            onTap: model.busy || model.loading ? null : () => inspect(item),
          );
        },
        children: [
          SectionTitle(
            widget.group?.name ?? 'Invitations de responsables',
            subtitle: widget.group == null
                ? 'Accès pour créer un groupe partenaire.'
                : 'Suivez les accès accordés dans ce groupe.',
          ),
          FilledButton.icon(
            onPressed: model.busy || model.loading ? null : invite,
            icon: const Icon(AppIcons.personAddAlt),
            label: const Text('Nouvelle invitation'),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Afficher les invitations retirées'),
            value: model.archived,
            onChanged: model.loading || model.busy
                ? null
                : (value) {
                    model.archived = value;
                    model.load();
                  },
          ),
          if (model.loading) const LinearProgressIndicator(),
          if (model.error != null)
            Notice(model.error!, error: true, retry: model.load),
          if (!model.loading && model.error == null && model.items.isEmpty)
            const EmptyState(
              title: 'Aucune invitation',
              description: 'Vos invitations apparaîtront ici avec leur état et leur date de validité.',
            ),
        ],
      ),
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

  Future<void> inspect(Invitation item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .78,
        child: Content(
          children: [
            SectionTitle(
              item.email,
              subtitle: '${item.roleLabel} · ${item.statusLabel}',
            ),
            if (item.storeIds.isNotEmpty)
              Text(
                widget.workspace.state.stores
                    .where((s) => item.storeIds.contains(s.id))
                    .map((s) => s.name)
                    .join(', '),
              ),
            const SizedBox(height: 16),
            Text(
              'Le code expire le ${TunisDates.timestampLabel(item.expiresAt)} et devient inutilisable après activation.',
            ),
            if (item.status == 'accepted' || item.status == 'closed') ...[
              const SizedBox(height: 12),
              const Text(
                'Pour désactiver une personne, ouvrez son accès dans l’équipe. Retirer cette invitation ne modifie pas son compte.',
              ),
            ],
            const SizedBox(height: 24),
            if (item.canResend)
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'resend'),
                icon: const Icon(AppIcons.mailOutline),
                label: const Text('Renvoyer un nouveau code'),
              ),
            if (item.canRevoke) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, 'revoke'),
                child: const Text('Révoquer l’invitation'),
              ),
            ],
            if (item.canArchive) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context, 'archive'),
                child: const Text('Retirer de la liste'),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    final message = switch (action) {
      'resend' =>
        'Un nouveau code sera envoyé à ${item.email}. L’ancien code ne fonctionnera plus.',
      'revoke' =>
        'Le code envoyé à ${item.email} sera désactivé. Son compte existant, s’il en a un, sera conservé.',
      _ => 'Cette invitation sera masquée et son code désactivé si elle est encore en attente. L’historique et les comptes seront conservés.',
    };
    if (!await confirmAction(context, 'Confirmer cette action', message) ||
        !mounted) {
      return;
    }
    final success = await model.act(item, action);
    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'resend'
                ? 'Nouvelle invitation envoyée.'
                : 'Invitation mise à jour.',
          ),
        ),
      );
    }
  }
}
