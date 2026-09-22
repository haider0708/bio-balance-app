import '../../core/navigation.dart';

import 'dart:async';

import '../../../data/repositories/store_settings_repository.dart';
import 'store_settings_screen.dart';
import 'product_settings_screen.dart';
import '../media/image_input.dart';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../workspace/workspace_view_model.dart';
import '../workspace/operations_screens.dart';
import '../workspace/team_rewards_orders.dart';

class StoresPage extends StatefulWidget {
  final WorkspaceViewModel vm;
  const StoresPage({super.key, required this.vm});
  @override
  State<StoresPage> createState() => _StoresPageState();
}

class _StoresPageState extends State<StoresPage> {
  String query = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.vm,
    builder: (context, _) => content(context),
  );
  Widget content(BuildContext context) {
    final vm = widget.vm;
    final stores = vm.state.stores
        .where(
          (s) => '${s.name} ${s.organizationName} ${s.city}'
              .toLowerCase()
              .contains(query),
        )
        .toList();
    return Content.builder(
      itemCount: stores.length,
      itemBuilder: (context, index) {
        final store = stores[index];
        return CompactRow(
          title: store.name,
          subtitle: [
            store.organizationName,
            store.city,
          ].where((s) => s.isNotEmpty).join(' · '),
          icon: store.imageId == null ? Icons.storefront_outlined : null,
          leading: store.imageId == null
              ? null
              : SizedBox(
                  width: 40,
                  child: ProtectedImage(vm: vm, id: store.imageId!, height: 40),
                ),
          selected: store.id == vm.state.store?.id,
          trailing: store.id == vm.state.store?.id
              ? const Icon(
                  Icons.check_circle_outline,
                  color: darkGreen,
                  semanticLabel: 'Magasin sélectionné',
                )
              : null,
          onTap: () => run(context, () => vm.select(store)),
        );
      },
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
        const SizedBox(height: 8),
        TextField(
          onChanged: (value) =>
              setState(() => query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            hintText: 'Magasin, organisation ou ville',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        if (stores.isEmpty)
          const EmptyState(
            title: 'Aucun magasin trouvé',
            description: 'Essayez un autre nom ou une autre ville.',
          ),
      ],
    );
  }
}

Future<void> switchStore(BuildContext context, WorkspaceViewModel vm) async {
  final selected = await showModalBottomSheet<Store>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        _StorePicker(stores: vm.state.stores, selectedId: vm.state.store?.id),
  );
  if (selected != null && context.mounted) {
    await run(context, () => vm.select(selected));
  }
}

class _StorePicker extends StatefulWidget {
  final List<Store> stores;
  final String? selectedId;
  const _StorePicker({required this.stores, this.selectedId});
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
      height: MediaQuery.sizeOf(context).height * .85,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            const SliverToBoxAdapter(child: SectionTitle('Changer de magasin')),
            SliverToBoxAdapter(
              child: TextField(
                onChanged: (value) => setState(() => q = value.trim()),
                decoration: const InputDecoration(
                  hintText: 'Magasin, organisation ou ville',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (stores.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  title: 'Aucun magasin trouvé',
                  description: 'Essayez une autre recherche.',
                ),
              ),
            SliverList.builder(
              itemCount: stores.length,
              itemBuilder: (_, i) => CompactRow(
                title: stores[i].name,
                subtitle: stores[i].organizationName,
                icon: Icons.storefront_outlined,
                selected: stores[i].id == widget.selectedId,
                trailing: stores[i].id == widget.selectedId
                    ? const Icon(
                        Icons.check,
                        semanticLabel: 'Magasin sélectionné',
                      )
                    : null,
                onTap: () => Navigator.pop(context, stores[i]),
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
                ProductSettingsPage(vm: vm),
              ),
            ])
              CompactRow(
                title: step.$2,
                subtitle: progress[step.$1] == true ? 'Terminé' : 'À compléter',
                icon: progress[step.$1] == true
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
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
