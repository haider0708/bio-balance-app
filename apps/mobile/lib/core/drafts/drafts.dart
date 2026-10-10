import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../api/json.dart';
import '../auth/session.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback.dart';

/// Work in progress kept on the phone: a sale being built, a stock count, a restock request.
/// It is saved at every change, so leaving the screen, a phone call or the app being closed
/// never loses it. Each draft belongs to one account and is forgotten after [life].
class Drafts {
  const Drafts._();

  static String _key(String account, String name) => 'draft.$account.$name';

  static Json? read(
    SharedPreferences prefs,
    String account,
    String name, {
    required Duration life,
  }) {
    final raw = prefs.getString(_key(account, name));
    if (raw == null) return null;
    try {
      final saved = jsonDecode(raw) as Json;
      final at = DateTime.parse(saved['at'] as String);
      if (DateTime.now().difference(at) > life) {
        prefs.remove(_key(account, name)).ignore();
        return null;
      }
      return saved['data'] as Json;
    } catch (_) {
      // Written by another version, or damaged: start afresh.
      prefs.remove(_key(account, name)).ignore();
      return null;
    }
  }

  /// Saves [data], or removes the draft when it is null.
  static Future<void> write(
    SharedPreferences prefs,
    String account,
    String name,
    Json? data,
  ) => data == null
      ? prefs.remove(_key(account, name))
      : prefs.setString(
          _key(account, name),
          jsonEncode({'at': DateTime.now().toIso8601String(), 'data': data}),
        );

  /// Every draft of [account] (when the account is deleted).
  static Future<void> forget(SharedPreferences prefs, String account) async {
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith('draft.$account.')) await prefs.remove(key);
    }
  }
}

/// Keeps one screen's draft. The screen reads [restored] once, calls [save] after every change
/// and [discard] once the work is sent.
class DraftKeeper {
  DraftKeeper(this._ref, this.name, {required this.life});

  final WidgetRef _ref;
  final String name;
  final Duration life;
  bool _done = false;

  /// True once the work was sent: nothing is kept any more.
  bool get done => _done;

  SharedPreferences? get _prefs => _ref.read(preferencesProvider).value;
  String? get _account => _ref.read(accountProvider);

  /// The draft left last time, if any.
  Json? get restored {
    final prefs = _prefs;
    final account = _account;
    if (prefs == null || account == null) return null;
    return Drafts.read(prefs, account, name, life: life);
  }

  /// Saves the current state; an empty form ([data] null) leaves no draft.
  void save(Json? data) {
    final prefs = _prefs;
    final account = _account;
    if (_done || prefs == null || account == null) return;
    Drafts.write(prefs, account, name, data).ignore();
  }

  /// The work was sent or thrown away: no draft any more, and later saves are ignored.
  void discard() {
    _done = true;
    final prefs = _prefs;
    final account = _account;
    if (prefs == null || account == null) return;
    Drafts.write(prefs, account, name, null).ignore();
  }

  /// Starting over is allowed again after [discard] (the person cleared the form).
  void reopen() => _done = false;
}

/// "Your unfinished entry is back", with a way to start over.
class DraftNotice extends StatelessWidget {
  const DraftNotice({required this.onStartOver, super.key});

  final VoidCallback onStartOver;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: context.colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            LucideIcons.history,
            size: 18,
            color: context.colors.onPrimaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t.draftRestored,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onPrimaryContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              final yes = await confirm(
                context,
                title: t.startOverTitle,
                message: t.startOverBody,
                confirmLabel: t.startOver,
                destructive: true,
              );
              if (yes) onStartOver();
            },
            child: Text(t.startOver),
          ),
        ],
      ),
    );
  }
}

/// Tells the person, as they leave, that what they entered is kept for later.
class DraftLeaveNote extends StatelessWidget {
  const DraftLeaveNote({required this.pending, required this.child, super.key});

  /// Whether something would be kept if the person left now (asked at that moment).
  final bool Function() pending;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop || !pending()) return;
      final t = AppLocalizations.of(context);
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(t.draftKept)));
    },
    child: child,
  );
}
