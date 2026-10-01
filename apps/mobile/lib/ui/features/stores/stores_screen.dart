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
import '../authentication/session_view_model.dart';
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
  // What the server last said, so a tick shows at once and never waits for a full sync.
  Map<String, dynamic>? latest;
  int? latestVersion;
  int pending = 0;
  Future<void> _queue = Future.value();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.vm,
    builder: (context, _) {
      final vm = widget.vm;
      // Once the synchronized workspace has caught up, it is the source again.
      final seen = integer((vm.state.data?.raw['store'] as Map?)?['version']);
      if (pending == 0 &&
          latest != null &&
          seen >= (latestVersion ?? 1 << 30)) {
        latest = null;
      }
      final progress =
          latest ??
          Map<String, dynamic>.from(vm.state.data?.raw['onboarding'] ?? {});
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
              onChanged: (value) => choice('workingAlone', value ?? false),
            ),
            CheckboxListTile(
              value: progress['noOpeningStock'] == true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Je n’ai pas de stock de départ'),
              subtitle: const Text(
                'Vos produits arriveront par commande et livraison. Vous pouvez changer d’avis tant que vous n’avez pas de stock.',
              ),
              onChanged: (value) => choice('noOpeningStock', value ?? false),
            ),
            if ((progress['incompleteProducts'] as List? ?? []).isNotEmpty)
              Notice(
                '${(progress['incompleteProducts'] as List).length} produit(s) restent à paramétrer : indiquez leur prix.',
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

  /// The box flips immediately; the server is told in order, one request at a time,
  /// and the answer (not a full synchronization) refreshes the progress.
  Future<void> choice(String key, bool value) {
    pending++;
    setState(() => latest = {...(latest ?? _progress), key: value});
    return _queue = _queue.catchError((Object _) {}).then((_) async {
      try {
        widget.vm.requireAccess(store, 'manage');
        final result = await StoreSettingsRepository(widget.vm.api)
            .onboarding(store, {
              key: value,
              'expectedVersion':
                  latestVersion ??
                  (widget.vm.state.data!.raw['store'] as Map)['version'],
            });
        latestVersion = integer((result['store'] as Map)['version']);
        if (mounted && pending == 1) {
          setState(
            () => latest = Map<String, dynamic>.from(result['onboarding']),
          );
        }
        // The rest of the workspace catches up in the background.
        unawaited(widget.vm.synchronize().catchError((Object _) {}));
      } catch (e) {
        if (!mounted) return;
        setState(() => latest = null);
        latestVersion = null;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(SessionViewModel.message(e))));
      }
    });
  }

  Map<String, dynamic> get _progress =>
      Map<String, dynamic>.from(widget.vm.state.data?.raw['onboarding'] ?? {});

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
