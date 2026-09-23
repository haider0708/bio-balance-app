import 'package:flutter/material.dart';

import '../../core/design.dart';
import '../../../domain/models/models.dart';
import 'scope_view_model.dart';
import 'operation_helpers.dart';

class ScopeHeader extends StatelessWidget {
  final ScopeViewModel vm;
  const ScopeHeader({super.key, required this.vm});
  @override
  Widget build(BuildContext context) {
    final canBrowse =
        vm.workspace.user.admin ||
        vm.groups.any((g) => g.canManage) ||
        vm.groups.length > 1 ||
        vm.stores.length > 1;
    return Semantics(
      label: 'Groupe sélectionné',
      child: InkWell(
        key: const ValueKey('scope.group'),
        borderRadius: BorderRadius.circular(10),
        onTap: canBrowse && !vm.switching ? () => groups(context) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BIOBALANCE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: darkGreen,
                      ),
                    ),
                    Text(
                      vm.scope.group?.name ??
                          (vm.workspace.user.admin
                              ? 'Tous les groupes'
                              : 'Mon espace'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (canBrowse)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    AppIcons.keyboardArrowDown,
                    size: 18,
                    color: darkGreen,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> groups(BuildContext context) async {
    final options = [
      if (vm.workspace.user.admin)
        (id: '', title: 'Tous les groupes', subtitle: 'Vue du réseau'),
      for (final g in vm.groups)
        (id: g.id, title: g.name, subtitle: '${g.storeCount} magasin(s)'),
    ];
    final id = await pickScope(
      context,
      title: 'Choisir un groupe',
      options: options,
      selected: vm.scope.group?.id ?? '',
    );
    if (id != null && context.mounted) {
      final group = id.isEmpty ? null : vm.groups.firstWhere((g) => g.id == id);
      if (group != null && !vm.workspace.user.admin && !group.canManage) {
        final stores = vm.storesFor(group.id);
        if (stores.length > 1) {
          final store = await Navigator.of(context).push<Store>(
            MaterialPageRoute(
              builder: (page) => Scaffold(
                appBar: AppBar(title: Text(group.name)),
                body: Content(
                  children: [
                    const SectionTitle(
                      'Vos magasins',
                      subtitle:
                          'Choisissez le magasin dans lequel vous travaillez.',
                    ),
                    for (final entry in stores)
                      CompactRow(
                        title: entry.name,
                        subtitle: entry.city,
                        icon: AppIcons.storefrontOutlined,
                        onTap: () => Navigator.of(page).pop(entry),
                      ),
                  ],
                ),
              ),
            ),
          );
          if (store != null && context.mounted) {
            await run(context, () => vm.selectAssignedStore(group, store));
          }
          return;
        }
      }
      await run(context, () => vm.selectGroup(group));
    }
  }
}

typedef ScopeOption = ({String id, String title, String subtitle});
Future<String?> pickScope(
  BuildContext context, {
  required String title,
  required List<ScopeOption> options,
  String? selected,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _Picker(title: title, options: options, selected: selected),
);

class _Picker extends StatefulWidget {
  final String title;
  final List<ScopeOption> options;
  final String? selected;
  const _Picker({required this.title, required this.options, this.selected});
  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final items = widget.options
        .where((o) => '${o.title} ${o.subtitle}'.toLowerCase().contains(query))
        .toList();
    return FractionallySizedBox(
      heightFactor: .85,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Content.builder(
          itemCount: items.length,
          itemBuilder: (_, i) => CompactRow(
            title: items[i].title,
            subtitle: items[i].subtitle,
            selected: widget.selected == items[i].id,
            trailing: widget.selected == items[i].id
                ? const Icon(
                    AppIcons.check,
                    semanticLabel: 'Sélection actuelle',
                  )
                : null,
            onTap: () => Navigator.pop(context, items[i].id),
          ),
          children: [
            SectionTitle(widget.title),
            TextField(
              onChanged: (v) => setState(() => query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Rechercher',
                prefixIcon: Icon(AppIcons.search),
              ),
            ),
            if (items.isEmpty)
              const EmptyState(
                title: 'Aucun résultat',
                description: 'Essayez un autre nom.',
              ),
          ],
        ),
      ),
    );
  }
}
