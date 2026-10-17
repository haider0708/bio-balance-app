import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../api/api_exception.dart';
import '../l10n/server_text.dart';
import 'states.dart';

/// Shows loading, an error with a retry button, or the data — the same way on every screen.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    required this.value,
    required this.builder,
    this.onRetry,
    this.isEmpty,
    this.empty,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const LoadingState(),
      error: (error, _) => ErrorState(error: error, onRetry: onRetry),
      data: (data) => isEmpty?.call(data) ?? false
          ? (empty ?? const SizedBox.shrink())
          : builder(data),
    );
  }
}

/// Turns any thrown object into a sentence a person can act on.
String errorMessage(BuildContext context, Object error) {
  final t = AppLocalizations.of(context);
  if (error is ApiException) {
    if (error.isOffline) return t.errorOffline;
    final text = ServerText.error(t, error);
    // A quantity below what already left the place: say which products, and how low each may go.
    final details = error.details;
    if (error.code == 'BELOW_SOLD' && details is Map) {
      final lines = [
        for (final p in (details['products'] as List? ?? const []))
          if (p is Map)
            t.belowSoldLine(
              '${p['name']}',
              (p['minimum'] as num?)?.toInt() ?? 0,
            ),
      ];
      if (lines.isNotEmpty) return '$text\n${lines.join('\n')}';
    }
    return text;
  }
  return t.errorGeneric;
}
