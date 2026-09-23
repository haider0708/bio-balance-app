import '../inventory/inventory_screens.dart';
import '../team/team_screen.dart';
import '../workspace/operation_helpers.dart';
import '../../core/navigation.dart';

import 'dart:async';

import '../../../data/repositories/store_settings_repository.dart';
import 'store_settings_screen.dart';
import 'product_settings_screen.dart';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../workspace/workspace_view_model.dart';

Future<void> inviteManager(BuildContext context, WorkspaceViewModel vm) async {
  await openEditor(
    context,
    title: 'Inviter un responsable',
    description: 'Après activation, cette personne créera son groupe puis ses magasins. Chaque responsable invité possède l’accès complet à son groupe.',
    fields: const [FieldSpec('email', 'Email du responsable')],
    submit: (v) async {
      await vm.teams.invite({
        ...v,
        'kind': 'new_group',
        'permissions': ['manage', 'sell', 'receive'],
      });
    },
    submitLabel: 'Envoyer l’invitation',
  );
}

class OnboardingScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  const OnboardingScreen({super.key, required this.vm});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool saving = false;
  late final store = widget.vm.state.store!;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.vm,
    builder: (context, _) {
      final vm = widget.vm,
          progress = Map<String, dynamic>.from(
            vm.state.data?.raw['onboarding'] ?? {},
          );
      final complete = progress['complete'] == true;
      return Scaffold(
        appBar: AppBar(title: const Text('Préparer votre magasin')),
        body: Content(
          maxWidth: 760,
          children: [
            SectionTitle(
              store.name,
              subtitle:
                  'Vous pouvez interrompre le guide et y revenir depuis Plus.',
            ),
            Text('${progress['completedCount'] ?? 0} étapes sur 4 terminées'),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: integer(progress['completedCount']) / 4,
            ),
            const SizedBox(height: 20),
            for (final step in [
              ('profile', 'Informations du magasin', StoreSettingsPage(vm: vm)),
              ('team', 'Inviter votre équipe', TeamPage(vm: vm)),
              ('stock', 'Saisir les lots et le stock', StockPage(vm: vm)),
              (
                'products',
                'Configurer prix, seuils et points',
                ProductSettingsPage(vm: vm),
              ),
            ])
              CompactRow(
                title: step.$2,
                subtitle: progress[step.$1] == true ? 'Terminé' : 'À compléter',
                icon: progress[step.$1] == true
                    ? AppIcons.checkCircleOutline
                    : AppIcons.radioButtonUnchecked,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(step.$2)),
                      body: step.$3,
                    ),
                  ),
                ),
              ),
            CheckboxListTile(
              value: progress['workingAlone'] == true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Je travaille seul pour le moment'),
              subtitle: const Text(
                'Vous pourrez inviter votre équipe plus tard.',
              ),
              onChanged: saving
                  ? null
                  : (value) => choice({'workingAlone': value}),
            ),
            CheckboxListTile(
              value: progress['noOpeningStock'] == true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Je n’ai pas de stock de départ'),
              subtitle: const Text(
                'Vous saisirez les lots lors de la première réception.',
              ),
              onChanged: saving
                  ? null
                  : (value) => choice({'noOpeningStock': value}),
            ),
            if ((progress['incompleteProducts'] as List? ?? []).isNotEmpty)
              Notice(
                '${(progress['incompleteProducts'] as List).length} produit(s) restent à paramétrer. Confirmez explicitement les produits à zéro point.',
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: !complete || saving ? null : finish,
              child: const Text('Terminer le guide'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continuer plus tard'),
            ),
          ],
        ),
      );
    },
  );
  Future<void> choice(Json values) async {
    setState(() => saving = true);
    await run(context, () async {
      widget.vm.requireAccess(store, 'manage');
      await StoreSettingsRepository(widget.vm.api).onboarding(store, {
        ...values,
        'expectedVersion':
            (widget.vm.state.data!.raw['store'] as Map)['version'],
      });
      await widget.vm.synchronize();
    });
    if (mounted) setState(() => saving = false);
  }

  Future<void> finish() async {
    setState(() => saving = true);
    await run(context, () async {
      widget.vm.requireAccess(store, 'manage');
      await StoreSettingsRepository(widget.vm.api)
          .onboarding(store, {'step': 5});
      await widget.vm.synchronize();
      if (mounted) completeRoute(context);
    });
    if (mounted) setState(() => saving = false);
  }
}
