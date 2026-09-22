import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class AccountScreen extends StatelessWidget {
  final WorkspaceViewModel vm;
  const AccountScreen({super.key, required this.vm});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mon compte')),
    body: Content(
      maxWidth: 640,
      children: [
        SectionTitle(vm.user.name, subtitle: vm.user.email),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.language),
          title: Text('Français · TND'),
          subtitle: Text('Montants en millimes · Dates jour/mois/année'),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.notifications_outlined),
          title: Text('Notifications dans l’application'),
          subtitle: Text(
            'Retrouvez les alertes et les messages dans votre boîte de notifications.',
          ),
        ),
        const SizedBox(height: 16),
        const SectionTitle('Besoin d’aide ?'),
        const Text(
          'Pour un problème de stock ou de récompense, contactez le responsable de votre magasin. Les opérations à vérifier sont conservées dans la synchronisation.',
        ),
        const SizedBox(height: 24),
        const Notice(
          'La déconnexion conserve les opérations en attente sur ce téléphone. Reconnectez-vous au même compte pour les synchroniser.',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () async {
            final session = context.read<SessionViewModel>();
            if (await confirmAction(
              context,
              'Se déconnecter ?',
              'Vos opérations locales seront conservées pour ce compte.',
            )) {
              await session.logout();
              if (context.mounted) {
                Navigator.popUntil(context, (route) => route.isFirst);
              }
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Se déconnecter'),
        ),
      ],
    ),
  );
}
