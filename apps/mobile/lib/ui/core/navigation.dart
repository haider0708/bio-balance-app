import 'package:flutter/material.dart';

/// A save can finish during the originating route's exit animation. `mounted`
/// alone is insufficient: popping the navigator then would remove its next route.
void completeRoute<T>(BuildContext context, [T? result]) {
  if (!context.mounted) return;
  final route = ModalRoute.of(context);
  if (route == null || !route.isActive || route.isFirst) return;
  final navigator = Navigator.of(context);
  if (route.isCurrent) {
    navigator.pop<T>(result);
  } else {
    navigator.removeRoute(route, result);
  }
}
