import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'sales_models.dart';

const _storageKey = 'outbox.sales';

/// Codes meaning "the server understood and said no": retrying would not help.
const _final = {
  'PDV_INACTIVE',
  'OUT_OF_STOCK',
  'PRODUCT_NOT_FOUND',
  'INVALID_DATE',
  'NO_LINES',
  'VALIDATION',
  'FORBIDDEN',
  'DUPLICATE_PRODUCT',
};

/// Sales made without a connection. They wait here, on the phone, and are sent
/// again (with the same id, so never twice) as soon as the server answers.
class SalesOutbox extends Notifier<List<PendingSale>>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _flushing = false;

  @override
  List<PendingSale> build() {
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _timer?.cancel();
    });
    _load();
    return const [];
  }

  Future<void> _load() async {
    final prefs = await ref.read(preferencesProvider.future);
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    state = jsonList(jsonDecode(raw)).map(PendingSale.fromJson).toList();
    _schedule();
  }

  Future<void> _save() async {
    final prefs = await ref.read(preferencesProvider.future);
    await prefs.setString(
      _storageKey,
      jsonEncode([for (final s in state) s.toJson()]),
    );
  }

  Future<void> add(PendingSale sale) async {
    state = [...state, sale];
    await _save();
    _schedule();
  }

  Future<void> discard(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _save();
  }

  @override
  // ignore: avoid_renaming_method_parameters
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) unawaited(flush());
  }

  void _schedule() {
    _timer?.cancel();
    if (state.any((s) => s.error == null))
      _timer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(flush()),
      );
  }

  /// Try to send everything waiting. Stops at the first connection problem.
  Future<void> flush() async {
    if (_flushing || ref.read(tokenProvider) == null) return;
    _flushing = true;
    try {
      for (final sale in state.where((s) => s.error == null).toList()) {
        try {
          await ref.read(apiClientProvider).post('/v1/sales', {
            'id': sale.id,
            'occurredAt': sale.occurredAt.toUtc().toIso8601String(),
            'lines': [
              for (final l in sale.lines)
                {'productId': l.productId, 'quantity': l.quantity},
            ],
          });
          state = state.where((s) => s.id != sale.id).toList();
        } on ApiException catch (error) {
          if (error.isOffline ||
              error.code == 'TIMEOUT' ||
              (error.status ?? 0) >= 500 ||
              error.isUnauthorized)
            break;
          if (_final.contains(error.code) ||
              error.status == 400 ||
              error.status == 403) {
            state = [
              for (final s in state)
                s.id == sale.id ? s.withError(error.code) : s,
            ];
          }
        }
      }
      await _save();
      _schedule();
    } finally {
      _flushing = false;
    }
  }
}

final salesOutboxProvider = NotifierProvider<SalesOutbox, List<PendingSale>>(
  SalesOutbox.new,
);
