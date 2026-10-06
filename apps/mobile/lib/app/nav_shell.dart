import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NavDestination {
  const NavDestination({required this.icon, required this.label, this.selectedIcon, this.badge});

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final int? badge;
}

/// The bottom bar around a role's main tabs. Each tab keeps its own place while you switch.
class NavShell extends StatelessWidget {
  const NavShell({required this.shell, required this.destinations, super.key});

  final StatefulNavigationShell shell;
  final List<NavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          for (final d in destinations)
            NavigationDestination(
              icon: Badge(isLabelVisible: (d.badge ?? 0) > 0, label: Text('${d.badge}'), child: Icon(d.icon)),
              selectedIcon: Badge(isLabelVisible: (d.badge ?? 0) > 0, label: Text('${d.badge}'), child: Icon(d.selectedIcon ?? d.icon)),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
