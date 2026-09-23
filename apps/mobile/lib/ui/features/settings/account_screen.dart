import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';
import '../notifications/notifications_screen.dart';
import '../synchronization/sync_screen.dart';

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
        const CompactRow(
          icon: AppIcons.language,
          title: 'Français · TND',
          subtitle: 'Dates au format jour/mois/année',
        ),
        CompactRow(
          icon: AppIcons.notificationsOutlined,
          title: 'Notifications',
          subtitle: 'Alertes et messages de votre équipe',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => NotificationsScreen(vm: vm)),
          ),
        ),
        CompactRow(
          icon: AppIcons.sync,
          title: 'Synchronisation',
          subtitle: 'Opérations en attente et état de connexion',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SyncScreen(vm: vm)),
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
              final signedOut = await session.logout();
              if (context.mounted && signedOut) {
                Navigator.popUntil(context, (route) => route.isFirst);
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      session.state.error ?? 'Déconnexion interrompue.',
                    ),
                  ),
                );
              }
            }
          },
          icon: const Icon(AppIcons.logout),
          label: const Text('Se déconnecter'),
        ),
      ],
    ),
  );
}
