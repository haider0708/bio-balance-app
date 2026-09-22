import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../workspace/workspace_view_model.dart';

import '../workspace/operation_helpers.dart';

class TeamPage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const TeamPage({super.key, required this.vm});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => content(context),
  );
  Widget content(BuildContext context) {
    final team = vm.state.data?.list('team') ?? [],
        invitations = vm.state.data?.list('invitations') ?? [];
    return Content.builder(
      itemCount: team.length + invitations.length,
      itemBuilder: (context, index) {
        if (index >= team.length) {
          final invitation = invitations[index - team.length];
          return CompactRow(
            title: invitation['email'],
            subtitle: 'Invité · activation attendue',
            icon: Icons.mark_email_unread_outlined,
          );
        }
        final member = team[index];
        final name = '${member['name'] ?? member['email'] ?? 'Membre'}';
        return CompactRow(
          title: name.isEmpty ? 'Membre' : name,
          subtitle:
              '${member['email'] ?? ''}\n${member['active'] == true ? 'Actif' : 'Désactivé'} · ${(member['permissions'] as List? ?? []).contains('manage') ? 'Responsable' : 'Vendeur'}',
          icon: Icons.person_outline,
          trailing: IconButton(
            tooltip: 'Gérer l’accès',
            icon: const Icon(Icons.manage_accounts_outlined),
            onPressed: member['userId'] == vm.user.id
                ? null
                : () => access(context, member),
          ),
        );
      },
      children: [
        SectionTitle(
          'Votre équipe',
          subtitle:
              '${team.length} membre(s) · ${invitations.length} invitation(s)',
          action: FilledButton.icon(
            onPressed: () => invite(context),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Inviter'),
          ),
        ),
        if (team.isEmpty && invitations.isEmpty)
          const EmptyState(
            title: 'Invitez votre premier collègue',
            description: 'Il recevra un email pour rejoindre ce magasin.',
          ),
      ],
    );
  }

  Future<void> invite(BuildContext context) async {
    final store = vm.state.store!;
    if (await openEditor(
      context,
      title: 'Inviter un membre',
      description: 'L’invitation concerne uniquement ${store.name}.',
      fields: const [
        FieldSpec('email', 'Adresse email'),
        FieldSpec(
          'role',
          'Permissions',
          initial: 'seller',
          options: {
            'seller': 'Vendeur : ventes et réceptions',
            'manager': 'Responsable du magasin',
          },
        ),
      ],
      submit: (v) async {
        await vm.teams.invite({
          'email': v['email'],
          'organizationId': store.organizationId,
          'storeId': store.id,
          'permissions': v['role'] == 'manager'
              ? ['manage', 'sell', 'receive']
              : ['sell', 'receive'],
        });
      },
    )) {
      await vm.synchronize();
    }
  }

  Future<void> access(BuildContext context, Json member) async {
    final store = vm.state.store!;
    if (await confirmAction(
      context,
      member['active'] == true
          ? 'Désactiver cet accès ?'
          : 'Réactiver cet accès ?',
      "L’historique des ventes et l’identité de ce membre seront conservés.",
    )) {
      if (!context.mounted) return;
      await run(context, () async {
        await vm.teams.setAccess(
          store,
          member['userId'],
          active: member['active'] != true,
          permissions: List<String>.from(member['permissions']),
        );
        await vm.synchronize();
      });
    }
  }
}
