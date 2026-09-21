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
  Widget build(BuildContext context) {
    final team = vm.state.data?.list('team') ?? [],
        invitations = vm.state.data?.list('invitations') ?? [];
    return Content(
      children: [
        SectionTitle(
          'Votre équipe',
          subtitle: 'Un accès personnel, une activité toujours attribuée.',
          action: FilledButton.icon(
            onPressed: () => invite(context),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('Inviter'),
          ),
        ),
        ...team.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFEBF5E7),
                  child: Text(
                    (m['name'] ?? '?').toString().substring(0, 1).toUpperCase(),
                  ),
                ),
                title: Text(m['name'] ?? m['email'] ?? ''),
                subtitle: Text(
                  '${m['email']}\n${m['active'] == true ? 'Actif' : 'Désactivé'} · ${(m['permissions'] as List).contains('manage') ? 'Responsable' : 'Vendeur'}',
                ),
                trailing: IconButton(
                  onPressed: m['userId'] == vm.user.id
                      ? null
                      : () => access(context, m),
                  tooltip: 'Gérer l’accès',
                  icon: const Icon(Icons.manage_accounts_outlined),
                ),
              ),
            ),
          ),
        ),
        if (invitations.isNotEmpty) ...[
          const SizedBox(height: 24),
          const SectionTitle('Invitations en attente'),
          ...invitations.map(
            (i) => ListTile(
              leading: const Icon(Icons.mark_email_unread_outlined),
              title: Text(i['email']),
              subtitle: const Text('Invité · activation attendue'),
            ),
          ),
        ],
        if (team.isEmpty && invitations.isEmpty)
          const EmptyState(
            title: 'Invitez votre premier collègue',
            description: 'Il recevra un email pour créer son mot de passe et rejoindre ce magasin.',
          ),
      ],
    );
  }

  Future<void> invite(BuildContext context) async {
    if (await openEditor(
      context,
      title: 'Inviter un membre',
      description: 'L’invitation concerne uniquement ${vm.state.store!.name}.',
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
        await vm.request(
          'POST',
          '/v1/identity/invitations',
          body: {
            'email': v['email'],
            'organizationId': vm.state.store!.organizationId,
            'storeId': vm.state.store!.id,
            'permissions': v['role'] == 'manager'
                ? ['manage', 'sell', 'receive']
                : ['sell', 'receive'],
          },
        );
      },
    )) {
      await vm.synchronize();
    }
  }

  Future<void> access(BuildContext context, Json member) async {
    if (await confirmAction(
      context,
      member['active'] == true
          ? 'Désactiver cet accès ?'
          : 'Réactiver cet accès ?',
      "L’historique des ventes et l’identité de ce membre seront conservés.",
    )) {
      if (!context.mounted) return;
      await run(context, () async {
        await vm.storeRequest(
          'PATCH',
          'team/${member['userId']}',
          body: {
            'active': member['active'] != true,
            'permissions': member['permissions'],
          },
        );
        await vm.synchronize();
      });
    }
  }
}
