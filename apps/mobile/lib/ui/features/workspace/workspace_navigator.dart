import '../../core/app_icons.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'scope_screen.dart';
import 'workspace_view_model.dart';

/// Replaces protected routes only after their drafts have been persisted.
class WorkspaceNavigator extends StatefulWidget {
  const WorkspaceNavigator({super.key});
  @override
  State<WorkspaceNavigator> createState() => _WorkspaceNavigatorState();
}

class _WorkspaceNavigatorState extends State<WorkspaceNavigator> {
  var navigator = GlobalKey<NavigatorState>();
  int? revision;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WorkspaceViewModel>();
    if (revision != vm.accessRevision) {
      revision = vm.accessRevision;
      navigator = GlobalKey<NavigatorState>();
    }
    return Stack(
      children: [
        AbsorbPointer(
          absorbing: vm.securingAccess,
          child: NavigatorPopHandler<Object?>(
            onPopWithResult: (_) {
              unawaited(navigator.currentState!.maybePop());
            },
            child: Navigator(
              key: navigator,
              onGenerateRoute: (_) =>
                  MaterialPageRoute<void>(builder: (_) => const ScopeScreen()),
            ),
          ),
        ),
        if (vm.securingAccess)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(AppIcons.lockOutline, size: 40),
                        const SizedBox(height: 16),
                        Text(
                          vm.state.error ?? 'Enregistrement des brouillons…',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => vm.denyAccess(vm.state.store?.id),
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
