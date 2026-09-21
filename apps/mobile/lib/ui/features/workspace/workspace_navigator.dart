import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'workspace_screen.dart';
import 'workspace_view_model.dart';

/// Replaces protected routes only after their drafts have been persisted.
class WorkspaceNavigator extends StatelessWidget {
  const WorkspaceNavigator({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WorkspaceViewModel>();
    return Stack(
      children: [
        AbsorbPointer(
          absorbing: vm.securingAccess,
          child: Navigator(
            key: ValueKey(vm.accessRevision),
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => const WorkspaceScreen(),
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
                        const Icon(Icons.lock_outline, size: 40),
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
