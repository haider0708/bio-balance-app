import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../core/layout/layout.dart';
import '../core/theme/app_theme.dart';

class NavDestination {
  const NavDestination({required this.icon, required this.label, this.badge});

  final IconData icon;
  final String label;
  final int? badge;
}

/// The tabs of the app. On a phone a docked bottom bar (flush, hairline top, solid selected
/// state); on a tablet a rail down the side, with the page at a readable width beside it.
class NavShell extends StatelessWidget {
  const NavShell({required this.shell, required this.destinations, super.key});

  final StatefulNavigationShell shell;
  final List<NavDestination> destinations;

  void _go(int i) {
    unawaited(HapticFeedback.selectionClick());
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    if (MediaQuery.sizeOf(context).width >= wideBreakpoint) {
      return Scaffold(
        body: Row(
          children: [
            Material(
              color: s.card,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: s.hairline)),
                ),
                child: SafeArea(
                  right: false,
                  child: SizedBox(
                    width: 96,
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        for (var i = 0; i < destinations.length; i++)
                          SizedBox(
                            height: 76,
                            child: _Tab(
                              destination: destinations[i],
                              selected: i == shell.currentIndex,
                              onTap: () => _go(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                  child: shell,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: Material(
        color: s.card,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: s.hairline)),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 4),
            child: SizedBox(
              height: 60,
              child: Row(
                children: [
                  for (var i = 0; i < destinations.length; i++)
                    Expanded(
                      child: _Tab(
                        destination: destinations[i],
                        selected: i == shell.currentIndex,
                        onTap: () => _go(i),
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
    final primary = context.colors.primary;
    final badge = destination.badge ?? 0;
    final media = MediaQuery.of(context);
    final color = selected ? primary : s.muted;

    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(maxScaleFactor: 1.15),
      ),
      child: Semantics(
        selected: selected,
        button: true,
        label: destination.label,
        child: InkWell(
          onTap: onTap,
          splashColor: primary.withValues(alpha: 0.08),
          highlightColor: primary.withValues(alpha: 0.04),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 28,
                height: 3,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: selected ? primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                child: AnimatedScale(
                  scale: selected ? 1.05 : 1,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: Icon(destination.icon, size: 22, color: color),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: context.text.labelSmall!.copyWith(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0.1,
                  color: color,
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
      ),
    );
  }
}
