import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/photo_set.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../l10n/app_localizations.dart';
import '../approvals/approvals_repository.dart';
import 'stock_models.dart';
import 'stock_repository.dart';

/// Correcting a count. The responsable: a waiting one (it is on hold for the admin meanwhile, and the
/// hold is renewed while this screen is open) or an approved one once the admin approved her request.
/// The admin: any waiting or approved count, directly, with a reason once it is approved. The stock
/// follows the difference; the sales made since are never touched.
class EditDeclarationScreen extends ConsumerStatefulWidget {
  const EditDeclarationScreen({required this.declaration, super.key});

  final StockDeclaration declaration;

  @override
  ConsumerState<EditDeclarationScreen> createState() =>
      _EditDeclarationScreenState();
}

class _EditDeclarationScreenState extends ConsumerState<EditDeclarationScreen> {
  late final _quantities = QuantityController([
    for (final l in widget.declaration.lines)
      QuantityItem(
        productId: l.productId,
        name: l.name,
        family: l.family,
        quantity: l.quantity,
      ),
  ]);
  late final _note = TextEditingController(text: widget.declaration.note ?? '');
  final _reason = TextEditingController();
  late List<String> _photoIds = widget.declaration.photoIds.isNotEmpty
      ? widget.declaration.photoIds
      : [?widget.declaration.photoId];
  bool _photosBusy = false;
  bool _held = false;
  bool _saved = false;
  Timer? _renew;

  /// Kept from the start: `ref` cannot be used once the screen is closing (when the hold is released).
  late final StockRepository _stock = ref.read(stockRepositoryProvider);

  bool get _approved => widget.declaration.status == DeclarationStatus.approved;

  bool get _admin => ref.read(meProvider).role == Role.admin;

  @override
  void initState() {
    super.initState();
    if (!_approved && !_admin) unawaited(_hold());
  }

  /// Puts the waiting count on hold (and renews the hold while the screen is open).
  Future<void> _hold() async {
    try {
      await _stock.startEdit(widget.declaration.id);
      if (!mounted) return;
      setState(() => _held = true);
      _renew ??= Timer.periodic(
        const Duration(minutes: 10),
        (_) => unawaited(
          _stock.startEdit(widget.declaration.id).catchError((_) {}),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      showError(context, error);
      context.pop(false);
    }
  }

  @override
  void dispose() {
    _renew?.cancel();
    // Left without saving: the count goes back to the admin as it was.
    if (_held && !_saved) {
      unawaited(_stock.cancelEdit(widget.declaration.id).catchError((_) {}));
    }
    _quantities.dispose();
    _note.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final ok = await perform(
      context,
      () => ref
          .read(stockRepositoryProvider)
          .edit(
            widget.declaration.id,
            lines: _quantities.lines(),
            photoIds: _photoIds,
            note: _note.text.trim(),
            reason: _approved && _admin ? _reason.text.trim() : null,
            revision: widget.declaration.revision,
          ),
      success: _approved || _admin ? t.correctionSaved : t.declarationSent,
    );
    if (!ok) {
      // A count changed by someone else meanwhile: what is shown must be reloaded.
      ref.invalidate(declarationProvider(widget.declaration.id));
      return;
    }
    if (!mounted) return;
    _saved = true;
    ref
      ..invalidate(declarationProvider(widget.declaration.id))
      ..invalidate(declarationsProvider(widget.declaration.location.id))
      ..invalidate(stockLevelsProvider(widget.declaration.location.id))
      ..invalidate(approvalsProvider(null));
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final d = widget.declaration;
    return Scaffold(
      appBar: AppBar(title: Text(d.location.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _admin
                ? t.adminEditHint
                : _approved
                ? t.correctApprovedHint(
                    Dates.dateTime(
                      d.correction?.until ??
                          d.correctableUntil ??
                          DateTime.now(),
                      t.localeName,
                    ),
                  )
                : t.correctCountHint,
            style: context.text.bodyMedium?.copyWith(
              color: context.status.muted,
            ),
          ),
          const Gap(16),
          PhotoSet(
            label: t.photoOfStock,
            initialIds: _photoIds,
            onChanged: (ids, busy) => setState(() {
              _photoIds = ids;
              _photosBusy = busy;
            }),
          ),
          SectionHeader(t.countedProducts),
          QuantityEditor(
            controller: _quantities,
            addLabel: t.addProduct,
            allowPaste: true,
          ),
          const Gap(16),
          if (_approved && _admin) ...[
            TextField(
              controller: _reason,
              maxLength: 300,
              minLines: 1,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: t.correctionReason),
            ),
            const Gap(8),
          ],
          TextField(
            controller: _note,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(labelText: '${t.note} (${t.optional})'),
          ),
          const Gap(8),
          ListenableBuilder(
            listenable: _quantities,
            builder: (context, _) => AsyncButton(
              label: _approved || _admin ? t.saveCorrection : t.sendToAdmin,
              icon: _approved || _admin ? LucideIcons.check : LucideIcons.send,
              onPressed:
                  _photosBusy ||
                      (_photoIds.isEmpty && !_quantities.isEmpty) ||
                      (_approved && _admin && _reason.text.trim().length < 2) ||
                      (!_approved && !_admin && !_held)
                  ? null
                  : _save,
            ),
          ),
        ],
      ),
    );
  }
}
