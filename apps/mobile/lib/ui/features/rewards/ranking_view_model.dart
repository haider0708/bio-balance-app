import 'package:flutter/foundation.dart';

import '../../../domain/models/ranking.dart';
import '../authentication/session_view_model.dart';

@immutable
class RankingState {
  final StoreRanking? value;
  final bool loading;
  final String? error;
  const RankingState({this.value, this.loading = false, this.error});
}

/// One instance per store page. Refresh requests coalesce while one is active.
class RankingViewModel extends ChangeNotifier {
  final Future<StoreRanking> Function() read;
  RankingViewModel(this.read);
  RankingState state = const RankingState();
  bool _closed = false, _again = false;
  Future<void>? _pending;

  Future<void> refresh() {
    if (_closed) return Future.value();
    if (_pending != null) {
      _again = true;
      return _pending!;
    }
    return _pending = _load().whenComplete(() => _pending = null);
  }

  Future<void> _load() async {
    do {
      _again = false;
      state = RankingState(value: state.value, loading: true);
      notifyListeners();
      try {
        final value = await read();
        if (_closed) return;
        state = RankingState(value: value);
      } catch (e) {
        if (_closed) return;
        state = RankingState(
          value: state.value,
          error: SessionViewModel.message(e),
        );
      }
      notifyListeners();
    } while (_again && !_closed);
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
