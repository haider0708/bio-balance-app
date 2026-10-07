import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';

class NavDestination {
  const NavDestination({required this.icon, required this.label, this.badge});

  final IconData icon;
  final String label;
  final int? badge;
}

/// The floating, frosted bar around a role's main tabs. The selected tab grows into a
/// gradient pill with its label; each tab keeps its own place while you switch.
class NavShell extends StatelessWidget {
  const NavShell({required this.shell, required this.destinations, super.key});

  final StatefulNavigationShell shell;
  final List<NavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      body: shell,
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(14, 0, 14, bottom > 0 ? bottom : 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              height: 70,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: s.card.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: s.hairline),
                boxShadow: [
                  BoxShadow(
                    color: s.shadow,
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _Tab(
                        destination: destinations[i],
                        selected: i == shell.currentIndex,
                        onTap: () => shell.goBranch(
                          i,
                          initialLocation: i == shell.currentIndex,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final badge = destination.badge ?? 0;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: selected ? 54 : 40,
              height: 32,
              decoration: BoxDecoration(
                gradient: selected ? s.gradient : null,
                borderRadius: BorderRadius.circular(16),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: context.colors.primary.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Badge(
                  isLabelVisible: badge > 0,
                  label: Text('$badge'),
                  child: Icon(
                    destination.icon,
                    size: 21,
                    color: selected ? context.colors.onPrimary : s.muted,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: context.text.labelSmall!.copyWith(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? context.colors.primary : s.muted,
              ),
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
