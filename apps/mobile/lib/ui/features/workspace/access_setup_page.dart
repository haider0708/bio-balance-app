import 'package:flutter/material.dart';

import '../../core/design.dart';

/// Account activation is already complete here; setup and access refresh are
/// separate actions and neither one sends an invitation email.
class AccessSetupPage extends StatelessWidget {
  final String email;
  final bool canCreateGroup, refreshing;
  final VoidCallback onCreateGroup, onRefresh;
  const AccessSetupPage({
    super.key,
    required this.email,
    required this.canCreateGroup,
    required this.refreshing,
    required this.onCreateGroup,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) => Content(
    children: [
      const SectionTitle('Votre compte est activé'),
      Text(email, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 28),
      if (canCreateGroup) ...[
        const SectionTitle('Préparer mon activité'),
        const Text(
          'Créez votre groupe, puis votre premier magasin. Vous pourrez ensuite inviter votre équipe.',
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('access.create-group'),
          onPressed: refreshing ? null : onCreateGroup,
          icon: const Icon(AppIcons.add),
          label: const Text('Créer mon groupe'),
        ),
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 20),
      ] else ...[
        const SectionTitle('Aucun magasin attribué'),
        const Text(
          'Votre responsable doit vous donner accès à un magasin. Si vous avez reçu une invitation, activez son code depuis l’écran de connexion.',
        ),
        const SizedBox(height: 28),
      ],
      const SectionTitle('Mon accès a changé'),
      const Text(
        'Actualisez uniquement si un responsable vient de modifier vos accès. Cette action recherche vos groupes et magasins ; elle ne crée pas de compte et n’envoie pas d’email.',
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        key: const ValueKey('access.refresh'),
        onPressed: refreshing ? null : onRefresh,
        icon: const Icon(AppIcons.sync),
        label: Text(refreshing ? 'Vérification…' : 'Actualiser mes accès'),
      ),
    ],
  );
}
