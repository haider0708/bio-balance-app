import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/models/workspace_scope.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../media/image_input.dart';
import '../stores/stores_screen.dart';
import 'scope_view_model.dart';
import 'operation_helpers.dart';

class GroupOverviewLinks extends StatelessWidget {
  final ScopeViewModel scope;
  const GroupOverviewLinks({super.key, required this.scope});
  @override
  Widget build(BuildContext context) {
    final group = scope.scope.group!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (group.imageId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 72,
              child: ProtectedImage(
                vm: scope.workspace,
                id: group.imageId!,
                height: 72,
              ),
            ),
          ),
        SectionTitle(
          'Vos magasins',
          subtitle: '${scope.stores.length} magasin(s) dans ce groupe',
          action: TextButton.icon(
            onPressed: () =>
                run(context, () => createScopedStore(context, scope)),
            icon: const Icon(AppIcons.add),
            label: const Text('Ajouter'),
          ),
        ),
        if (scope.stores.isEmpty)
          const Text(
            'Créez votre premier magasin. Le guide vous accompagne ensuite pour l’équipe, le stock et les paramètres produits.',
          ),
        for (final store in scope.stores.take(5))
          CompactRow(
            title: store.name,
            subtitle:
                '${store.city}${store.onboardingStep < 5 ? ' · Configuration à terminer' : ''}',
            icon: AppIcons.storefrontOutlined,
            onTap: () => run(context, () => scope.selectStore(store)),
          ),
        if (scope.stores.length > 5)
          TextButton(
            onPressed: () => scope.setTab(1),
            child: const Text('Voir tous les magasins'),
          ),
        TextButton.icon(
          onPressed: () => editGroup(context, scope),
          icon: const Icon(AppIcons.settingsOutlined),
          label: const Text('Informations du groupe'),
        ),
      ],
    );
  }
}

Future<void> editGroup(BuildContext context, ScopeViewModel scope) async {
  final group = scope.scope.group!;
  if (await openEditor(
    context,
    title: 'Informations du groupe',
    draftKey: 'group-profile:${group.id}',
    fields: [
      FieldSpec('name', 'Nom du groupe', initial: group.name),
      FieldSpec(
        'phone',
        'Téléphone',
        initial: group.phone ?? '',
        required: false,
      ),
      FieldSpec(
        'imageId',
        'Photo ou logo',
        initial: group.imageId ?? '',
        required: false,
        imagePurpose: 'group',
        imageGroupId: group.id,
      ),
    ],
    submit: (v) => scope.repository.update(group.id, {
      'name': v['name'],
      'phone': v['phone'],
      'imageId': v['imageId']!.isEmpty ? null : v['imageId'],
      'expectedVersion': group.version,
    }),
  )) {
    await scope.refresh();
    final current = scope.groups.where((g) => g.id == group.id).firstOrNull;
    if (current != null) await scope.selectGroup(current);
  }
}

class GroupsPage extends StatefulWidget {
  final ScopeViewModel vm;
  final bool stores, allStores;
  const GroupsPage({
    super.key,
    required this.vm,
    this.stores = false,
    this.allStores = false,
  });
  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  String query = '';
  final search = TextEditingController();
  bool restored = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!restored) {
      query =
          PageStorage.maybeOf(context)
                  ?.readState(context, identifier: 'directory-query')
              as String? ??
          '';
      search.text = query;
      restored = true;
    }
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final groups = vm.groups
        .where((g) => g.name.toLowerCase().contains(query))
        .toList();
    final stores = (widget.allStores ? vm.workspace.state.stores : vm.stores)
        .where((s) => '${s.name} ${s.city}'.toLowerCase().contains(query))
        .toList();
    final count = widget.stores ? stores.length : groups.length;
    return Content.builder(
      key: PageStorageKey('directory:${vm.scope.key}'),
      itemCount: count,
      itemBuilder: (_, i) {
        final group = widget.stores ? null : groups[i],
            store = widget.stores ? stores[i] : null;
        final image = group?.imageId ?? store?.imageId;
        return CompactRow(
          title: group?.name ?? store!.name,
          subtitle: group != null
              ? '${group.storeCount} magasin(s)'
              : widget.allStores
              ? '${store!.organizationName} · ${store.city}'
              : store!.city,
          leading: image == null
              ? Icon(
                  widget.stores
                      ? AppIcons.storefrontOutlined
                      : AppIcons.groupsOutlined,
                  color: darkGreen,
                )
              : SizedBox(
                  width: 48,
                  child: ProtectedImage(
                    vm: vm.workspace,
                    id: image,
                    height: 48,
                  ),
                ),
          onTap: () => run(context, () async {
            if (group != null) {
              await vm.selectGroup(group);
              return;
            }
            if (widget.allStores) {
              final navigator = Navigator.of(context);
              await vm.selectGroup(
                vm.groups.firstWhere((g) => g.id == store!.organizationId),
              );
              await vm.selectStore(store);
              if (navigator.mounted) navigator.pop();
            } else {
              await vm.selectStore(store);
            }
          }),
        );
      },
      children: [
        SectionTitle(
          widget.stores
              ? (widget.allStores
                    ? 'Tous les magasins'
                    : 'Magasins de ${vm.scope.group!.name}')
              : 'Groupes partenaires',
          subtitle: widget.stores
              ? 'Chaque magasin conserve son stock, ses ventes et ses récompenses.'
              : 'Choisissez un groupe pour consulter son activité.',
          action: widget.stores && !widget.allStores
              ? FilledButton.icon(
                  onPressed: () => createScopedStore(context, vm),
                  icon: const Icon(AppIcons.add),
                  label: const Text('Ajouter un magasin'),
                )
              : null,
        ),
        if (!widget.stores && vm.workspace.user.admin)
          OutlinedButton.icon(
            onPressed: () => inviteManager(context, vm.workspace),
            icon: const Icon(AppIcons.personAddAlt),
            label: const Text('Inviter un responsable'),
          ),
        if (vm.grants.isNotEmpty)
          FilledButton.icon(
            onPressed: () => createGroup(context, vm),
            icon: const Icon(AppIcons.add),
            label: const Text('Créer mon groupe'),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: search,
          onChanged: (v) => setState(() {
            query = v.trim().toLowerCase();
            PageStorage.maybeOf(context)
                ?.writeState(context, query, identifier: 'directory-query');
          }),
          decoration: const InputDecoration(
            hintText: 'Rechercher par nom',
            prefixIcon: Icon(AppIcons.search),
          ),
        ),
        if (count == 0)
          EmptyState(
            title: query.isEmpty
                ? (widget.stores
                      ? 'Créons votre premier magasin'
                      : 'Aucun groupe pour le moment')
                : 'Aucun résultat',
            description: widget.stores
                ? 'Commencez par le nom et l’adresse. Le guide vous accompagne ensuite pour l’équipe et le stock.'
                : 'Les groupes apparaissent lorsque les responsables invités les créent.',
          ),
      ],
    );
  }
}

Future<void> createGroup(BuildContext context, ScopeViewModel vm) async {
  if (vm.grants.isEmpty) return;
  final grant = vm.grants.first;
  final prior = await vm.workspace.repository.draft(
    vm.workspace.user.id,
    '',
    'group-operation:$grant',
  );
  final operation = prior?['operationId'] ?? const Uuid().v4();
  await vm.workspace.repository.saveDraft(
    vm.workspace.user.id,
    '',
    'group-operation:$grant',
    {'operationId': operation},
  );
  if (!context.mounted) return;
  PartnerGroup? created;
  final saved = await openEditor(
    context,
    title: 'Créer votre groupe',
    description: 'Un groupe rassemble vos magasins et leurs responsables. Exemple : Parahouse. Vous ajouterez les magasins à l’étape suivante.',
    fields: const [
      FieldSpec('name', 'Nom du groupe'),
      FieldSpec('phone', 'Téléphone (facultatif)', required: false),
    ],
    submitLabel: 'Créer le groupe',
    draftKey: 'group-create:$grant',
    submit: (v) async {
      created = await vm.repository.create({
        ...v,
        'grantId': grant,
        'operationId': operation,
      });
    },
  );
  if (saved && created != null) {
    await vm.refresh();
    await vm.selectGroup(vm.groups.firstWhere((g) => g.id == created!.id));
  }
}

Future<void> createScopedStore(BuildContext context, ScopeViewModel vm) async {
  // Switching scope replaces the originating group page. Retain the navigator,
  // whose lifetime is independent of that page, for the next setup route.
  final navigator = Navigator.of(context);
  final group = vm.scope.group!;
  String? id;
  if (await openEditor(
    context,
    title: 'Ajouter un magasin',
    description:
        'Groupe : ${group.name}\nCe magasin aura son propre stock, ses ventes et ses récompenses.',
    draftKey: 'store-create:${group.id}',
    fields: const [
      FieldSpec('name', 'Nom du magasin'),
      FieldSpec('address', 'Adresse'),
      FieldSpec('city', 'Ville'),
      FieldSpec('phone', 'Téléphone (facultatif)', required: false),
    ],
    submit: (v) async {
      id = (await vm.workspace.stores.create({
        ...v,
        'organizationId': group.id,
      })).id;
    },
  )) {
    await vm.refresh();
    final store = vm.stores.where((s) => s.id == id).firstOrNull;
    if (store != null) {
      await vm.selectStore(store);
      if (navigator.mounted && !vm.closed) {
        await navigator.push(
          MaterialPageRoute(builder: (_) => OnboardingScreen(vm: vm.workspace)),
        );
      }
    }
  }
}
