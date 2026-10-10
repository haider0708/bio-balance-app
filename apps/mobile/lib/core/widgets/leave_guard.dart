import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'feedback.dart';

/// Asks before the back button or gesture throws away work in progress (a sale being built,
/// a stock count, an order). Saving and leaving by the app itself is never blocked.
class LeaveGuard extends StatelessWidget {
  const LeaveGuard({required this.dirty, required this.child, super.key});

  /// Whether leaving now would lose something.
  final bool dirty;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      final t = AppLocalizations.of(context);
      final leave = await confirm(
        context,
        title: t.leaveTitle,
        message: t.leaveMessage,
        confirmLabel: t.discard,
        destructive: true,
      );
      if (leave && context.mounted) Navigator.of(context).pop();
    },
    child: child,
  );
}
