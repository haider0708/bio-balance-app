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
      data: (data) => isEmpty?.call(data) == true ? (empty ?? const SizedBox.shrink()) : builder(data),
    );
  }
}

/// Turns any thrown object into a sentence a person can act on.
String errorMessage(BuildContext context, Object error) {
  final t = AppLocalizations.of(context);
  if (error is ApiException) {
    if (error.isOffline) return t.errorOffline;
    return ServerText.error(t, error);
  }
  return t.errorGeneric;
}
