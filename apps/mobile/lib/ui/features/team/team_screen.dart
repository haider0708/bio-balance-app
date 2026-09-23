import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/workspace_scope.dart';
import '../../../data/repositories/group_repository.dart';
import '../../core/design.dart';
import 'group_member_editor.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class TeamPage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const TeamPage({super.key, required this.vm});
  @override
  Widget build(BuildContext context) {
    final store = vm.state.store;
    if (store == null) {
      return const EmptyState(
        title: 'Choisissez un magasin',
        description: 'Son équipe appartient au groupe partenaire.',
      );
    }
    return GroupTeamPage(
      workspace: vm,
      group: PartnerGroup(
        id: store.organizationId,
        name: store.organizationName,
        canManage: true,
      ),
    );
  }
}

class GroupTeamViewModel extends ChangeNotifier {
  final WorkspaceViewModel workspace;
  late final repository = GroupRepository(
    workspace.repositoryContext,
    workspace.repository,
    workspace.user.id,
  );
  final PartnerGroup group;
  Json? data;
  String? error;
  bool loading = false, closed = false;
  StoreData? _data;
  GroupTeamViewModel(this.workspace, this.group) {
    _data = workspace.state.data;
    workspace.addListener(_changed);
  }
  void _changed() {
    if (!identical(_data, workspace.state.data)) {
      _data = workspace.state.data;
      load();
    }
  }

  Future<void> load() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final result = await repository.team(group.id);
      if (!closed) {
        data = result;
        error = null;
      }
    } catch (e) {
      if (!closed) error = SessionViewModel.message(e);
    } finally {
      loading = false;
      if (!closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    closed = true;
    workspace.removeListener(_changed);
    super.dispose();
  }
}

class GroupTeamPage extends StatefulWidget {
  final WorkspaceViewModel workspace;
  final PartnerGroup group;
  const GroupTeamPage({
    super.key,
    required this.workspace,
    required this.group,
  });
  @override
  State<GroupTeamPage> createState() => _GroupTeamPageState();
}

class _GroupTeamPageState extends State<GroupTeamPage> {
  late final vm = GroupTeamViewModel(widget.workspace, widget.group)..load();
  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => Content(
      children: [
        SectionTitle(
          'Équipe de ${widget.group.name}',
          subtitle: 'Les responsables gèrent tous les magasins. Les vendeurs accèdent uniquement aux magasins choisis.',
          action: FilledButton.icon(
            onPressed: () => edit(),
            icon: const Icon(AppIcons.personAddAlt),
            label: const Text('Inviter'),
          ),
        ),
        if (vm.loading) const LinearProgressIndicator(),
        if (vm.error != null) Notice(vm.error!, retry: vm.load),
        for (final member in objects(vm.data?['members']))
          CompactRow(
            title: member['name'],
            subtitle:
                '${member['role'] == 'responsible' ? 'Responsable · tout le groupe' : 'Vendeur · ${objects(widget.workspace.state.stores.map((s) => s.toJson()).toList()).where((s) => (member['storeIds'] as List).contains(s['id'])).map((s) => s['name']).join(', ')}'}\n${member['email']}',
            footer: StatusChip(
              member['active'] == true ? 'Actif' : 'Désactivé',
            ),
            icon: AppIcons.personOutline,
            onTap: () => edit(member),
          ),
        if (objects(vm.data?['invitations']).isNotEmpty)
          const SectionTitle('Invitations en attente'),
        for (final item in objects(vm.data?['invitations']))
          CompactRow(
            title: item['email'],
            subtitle: item['kind'] == 'responsible'
                ? 'Responsable du groupe'
                : 'Vendeur',
            footer: const StatusChip('En attente d’activation'),
            icon: AppIcons.mailOutline,
            onTap: () => edit(null, item),
          ),
        if (vm.data != null && objects(vm.data?['members']).isEmpty)
          const EmptyState(
            title: 'Ajoutez votre équipe',
            description: 'Chacun utilise son propre compte. Les activités restent attribuées à leur auteur.',
          ),
      ],
    ),
  );
  Future<void> edit([Json? member, Json? invitation]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupMemberEditor(
          workspace: widget.workspace,
          group: widget.group,
          member: member,
          invitation: invitation,
        ),
      ),
    );
    if (saved == true && mounted) await vm.load();
  }
}
