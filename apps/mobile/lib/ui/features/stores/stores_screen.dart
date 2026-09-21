import 'dart:async';

import '../../../data/repositories/store_settings_repository.dart';
import 'store_settings_screen.dart';
import '../media/image_input.dart';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../workspace/workspace_view_model.dart';
import '../workspace/operations_screens.dart';
import '../workspace/team_rewards_orders.dart';

class StoresPage extends StatelessWidget {
  final WorkspaceViewModel vm;
  const StoresPage({super.key, required this.vm});
  @override
  Widget build(BuildContext context) => Content(
    children: [
      SectionTitle(
        'Vos magasins',
        action: FilledButton.icon(
          onPressed: () => createStore(context, vm),
          icon: const Icon(Icons.add_business_outlined),
          label: const Text('Ajouter'),
        ),
      ),
      if (vm.user.admin)
        OutlinedButton(
          onPressed: () => inviteManager(context, vm),
          child: const Text('Inviter un responsable'),
        ),
      const SizedBox(height: 20),
      ...vm.state.stores.map(
        (s) => Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: s.imageId == null
                ? const Icon(Icons.storefront_outlined, color: darkGreen)
                : SizedBox(
                    width: 48,
                    child: ProtectedImage(vm: vm, id: s.imageId!, height: 48),
                  ),
            title: Text(s.name),
            subtitle: Text('${s.organizationName} · ${s.city}'),
            trailing: s.id == vm.state.store?.id
                ? const Icon(Icons.check_circle, color: darkGreen)
                : const Icon(Icons.chevron_right),
            onTap: () => vm.select(s),
          ),
        ),
      ),
    ],
  );
}

Future<void> switchStore(BuildContext context, WorkspaceViewModel vm) async {
  final selected = await showModalBottomSheet<Store>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _StorePicker(stores: vm.state.stores),
  );
  if (selected != null) await vm.select(selected);
}

class _StorePicker extends StatefulWidget {
  final List<Store> stores;
  const _StorePicker({required this.stores});
  @override
  State<_StorePicker> createState() => _StorePickerState();
}

class _StorePickerState extends State<_StorePicker> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final stores = widget.stores
        .where(
          (s) => '${s.name} ${s.organizationName} ${s.city}'
              .toLowerCase()
              .contains(q.toLowerCase()),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .7,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SectionTitle('Changer de magasin'),
            const Text(
              'Vos brouillons et vos opérations restent dans leur magasin d’origine.',
              style: TextStyle(fontSize: 14, color: muted),
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: const InputDecoration(
                hintText: 'Magasin, organisation ou ville',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: stores.length,
                itemBuilder: (_, i) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  leading: const Icon(Icons.storefront_outlined),
                  title: Text(stores[i].name),
                  subtitle: Text(stores[i].organizationName),
                  onTap: () => Navigator.pop(context, stores[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> createStore(BuildContext context, WorkspaceViewModel vm) async {
  await run(context, () async {
    final organizations = objects(await vm.stores.organizations());
    if (!context.mounted) return;
    if (organizations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'BioBalance doit d’abord vous accorder un accès responsable.',
          ),
        ),
      );
      return;
    }
    String? createdId;
    if (await openEditor(
      context,
      title: 'Créer votre magasin',
      fields: [
        FieldSpec(
          'organizationId',
          'Organisation',
          initial: organizations.first['id'],
          options: {for (final o in organizations) o['id']: o['name']},
        ),
        const FieldSpec('name', 'Nom du magasin'),
        const FieldSpec('address', 'Adresse'),
        const FieldSpec('city', 'Ville'),
        const FieldSpec('phone', 'Téléphone (facultatif)', required: false),
      ],
      submit: (v) async {
        final result = await vm.stores.create(v);
        createdId = result.id;
      },
    )) {
      await vm.initialize();
      final created = vm.state.stores
          .where((s) => s.id == createdId)
          .firstOrNull;
      if (created != null) await vm.select(created);
      if (context.mounted && created != null) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OnboardingScreen(vm: vm)),
        );
      }
    }
  });
}

Future<void> inviteManager(BuildContext context, WorkspaceViewModel vm) async {
  await openEditor(
    context,
    title: 'Accorder un accès responsable',
    fields: const [
      FieldSpec('email', 'Email du responsable'),
      FieldSpec('organizationName', 'Nom de l’organisation partenaire'),
    ],
    submit: (v) async {
      await vm.teams.invite({
        ...v,
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
                StockPage(vm: vm),
              ),
            ])
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: Icon(
                    progress[step.$1] == true
                        ? Icons.check_circle_outline
                        : Icons.radio_button_unchecked,
                    color: darkGreen,
                  ),
                  title: Text(step.$2),
                  subtitle: Text(
                    progress[step.$1] == true ? 'Terminé' : 'À compléter',
                  ),
                  trailing: const Icon(Icons.chevron_right),
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
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => saving = false);
  }
}
