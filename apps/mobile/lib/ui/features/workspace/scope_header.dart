import 'package:flutter/material.dart';

import '../../core/design.dart';
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
        vm.groups.length > 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _control(
            context,
            'Groupe',
            vm.scope.group?.name ?? 'Tous les groupes',
            AppIcons.groupsOutlined,
            canBrowse ? () => groups(context) : null,
            'scope.group',
          ),
          if (vm.scope.group != null)
            _control(
              context,
              'Magasin',
              vm.scope.store?.name ?? 'Tous les magasins',
              AppIcons.storefrontOutlined,
              () => stores(context),
              'scope.store',
            ),
          if (vm.switching) const LinearProgressIndicator(minHeight: 2),
        ],
      ),
    );
  }

  Widget _control(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    VoidCallback? onTap,
    String key,
  ) => Semantics(
    label: label,
    child: Material(
      color: const Color(0xFFF1F8F4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: ValueKey(key),
        onTap: vm.switching ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 20, color: darkGreen),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$label · ',
                        style: const TextStyle(color: muted, fontSize: 14),
                      ),
                      TextSpan(
                        text: value,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(AppIcons.keyboardArrowDown, size: 18),
            ],
          ),
        ),
      ),
    ),
  );
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
      await run(
        context,
        () => vm.selectGroup(
          id.isEmpty ? null : vm.groups.firstWhere((g) => g.id == id),
        ),
      );
    }
  }

  Future<void> stores(BuildContext context) async {
    final options = [
      if (vm.scope.group!.canManage || vm.workspace.user.admin)
        (
          id: '',
          title: 'Tous les magasins',
          subtitle: 'Résumé de ${vm.scope.group!.name}',
        ),
      for (final s in vm.stores) (id: s.id, title: s.name, subtitle: s.city),
    ];
    final id = await pickScope(
      context,
      title: vm.scope.group!.name,
      options: options,
      selected: vm.scope.store?.id ?? '',
    );
    if (id != null && context.mounted) {
      await run(
        context,
        () => vm.selectStore(
          id.isEmpty ? null : vm.stores.firstWhere((s) => s.id == id),
        ),
      );
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
