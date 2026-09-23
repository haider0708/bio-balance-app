import 'package:flutter/material.dart';

import 'design.dart';

/// Keeps the same destinations at every size, with a scrollable menu when
/// large text or a short viewport leaves too little room for readable tabs.
class WorkspaceNavigation extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onSelected;
  const WorkspaceNavigation({
    super.key,
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final media = MediaQuery.of(context);
      if (constraints.maxWidth < 360 ||
          media.size.height < 480 ||
          media.textScaler.scale(14) > 17.5) {
        return BottomAction(
          child: OutlinedButton.icon(
            key: const ValueKey('workspace.navigationMenu'),
            icon: const Icon(AppIcons.menu),
            label: Text('Menu · ${labels[selected]}'),
            onPressed: () => openMenu(context),
          ),
        );
      }
      // Team/catalogue remain directly available from Plus on narrow phones.
      final indices = labels.length == 5 && constraints.maxWidth < 440
          ? [0, 1, 2, 4]
          : List.generate(labels.length, (i) => i);
      return NavigationBar(
        animationDuration: media.disableAnimations || media.accessibleNavigation
            ? Duration.zero
            : const Duration(milliseconds: 180),
        height: 72,
        selectedIndex: indices.contains(selected)
            ? indices.indexOf(selected)
            : indices.length - 1,
        onDestinationSelected: (i) => onSelected(indices[i]),
        destinations: [
          for (final i in indices)
            NavigationDestination(
              key: ValueKey('workspace.destination.$i'),
              icon: Icon(icons[i]),
              label: switch (labels[i]) {
                'Vue d’ensemble' => 'Accueil',
                'Mes ventes' => 'Ventes',
                final label => label,
              },
              tooltip: labels[i],
            ),
        ],
      );
    },
  );

  Future<void> openMenu(BuildContext context) async {
    final index = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .85,
        child: Content(
          children: [
            const SectionTitle('Navigation'),
            for (var i = 0; i < labels.length; i++)
              CompactRow(
                key: ValueKey('workspace.menuDestination.$i'),
                title: labels[i],
                icon: icons[i],
                selected: selected == i,
                trailing: selected == i
                    ? const Icon(AppIcons.check, semanticLabel: 'Page actuelle')
                    : null,
                onTap: () => Navigator.pop(context, i),
              ),
          ],
        ),
      ),
    );
    if (index != null && context.mounted) onSelected(index);
  }
}
