import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import 'sales_models.dart';

/// One outbox per person: a sale is only ever sent under the account that made it.
String _storageKey(String userId) => 'outbox.sales.$userId';

/// Sales made without a connection. They wait here, on the phone, and are sent
/// again (with the same id, so never twice) as soon as the server answers.
class SalesOutbox extends Notifier<List<PendingSale>>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _flushing = false;
  String? _userId;

  @override
  List<PendingSale> build() {
    // Rebuilt when the person changes: each account sees and sends only its own sales.
    _userId = ref.watch(sessionProvider.select((s) => s.value?.me.id));
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _timer?.cancel();
    });
    if (_userId != null) unawaited(_load(_userId!));
    return const [];
  }

  Future<void> _load(String userId) async {
    final prefs = await ref.read(preferencesProvider.future);
    // Sales kept by an older version of the app, before outboxes were per person.
    final legacy = prefs.getString('outbox.sales');
    if (legacy != null && prefs.getString(_storageKey(userId)) == null) {
      await prefs.setString(_storageKey(userId), legacy);
      await prefs.remove('outbox.sales');
    }
    final raw = prefs.getString(_storageKey(userId));
    if (raw == null || _userId != userId) return;
    state = jsonList(jsonDecode(raw)).map(PendingSale.fromJson).toList();
    _schedule();
  }

  Future<void> _save() async {
    final userId = _userId;
    if (userId == null) return;
    final prefs = await ref.read(preferencesProvider.future);
    await prefs.setString(
      _storageKey(userId),
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
    final owner = _userId;
    if (_flushing || owner == null || ref.read(tokenProvider) == null) return;
    _flushing = true;
    try {
      for (final sale in state.where((s) => s.error == null).toList()) {
        // Another account signed in meanwhile: its token must never send this person's sales.
        if (_userId != owner || ref.read(accountProvider) != owner) return;
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
          final status = error.status ?? 0;
          // No answer, a server problem, a signed-out phone or "slow down": try again later.
          if (error.isOffline ||
              error.code == 'TIMEOUT' ||
              status >= 500 ||
              status == 429 ||
              error.isUnauthorized) {
            break;
          }
          // The server understood and said no: retrying would not help, so show it.
          state = [
            for (final s in state)
              s.id == sale.id ? s.withError(error.code) : s,
          ];
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
