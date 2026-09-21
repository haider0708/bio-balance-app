import 'dart:async';

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
            leading: const Icon(Icons.storefront_outlined, color: darkGreen),
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
    final organizations = objects(await vm.request('GET', '/v1/organizations'));
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
        await vm.request('POST', '/v1/stores', body: v);
      },
    )) {
      await vm.initialize();
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
      await vm.request(
        'POST',
        '/v1/identity/invitations',
        body: {
          ...v,
          'permissions': ['manage', 'sell', 'receive'],
        },
      );
    },
    submitLabel: 'Envoyer l’invitation',
  );
}

class OnboardingScreen extends StatelessWidget {
  final WorkspaceViewModel vm;
  const OnboardingScreen({super.key, required this.vm});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Préparer votre magasin')),
    body: Content(
      maxWidth: 760,
      children: [
        const SectionTitle(
          'Votre magasin, étape par étape',
          subtitle:
              'Vous pouvez interrompre ce guide et revenir à tout moment.',
        ),
        for (final step in [
          ('1', 'Votre magasin est créé', null),
          ('2', 'Inviter votre équipe', TeamPage(vm: vm)),
          ('3', 'Saisir les lots et le stock', StockPage(vm: vm)),
          ('4', 'Configurer les prix, seuils et points', StockPage(vm: vm)),
        ])
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFEBF5E7),
                child: Text(step.$1),
              ),
              title: Text(step.$2),
              trailing: step.$3 == null
                  ? const Icon(Icons.check, color: darkGreen)
                  : const Icon(Icons.chevron_right),
              onTap: step.$3 == null
                  ? null
                  : () => Navigator.push(
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
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () async {
            await vm.storeRequest('PATCH', 'onboarding', body: {'step': 5});
            await vm.synchronize();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Terminer le guide'),
        ),
      ],
    ),
  );
}
