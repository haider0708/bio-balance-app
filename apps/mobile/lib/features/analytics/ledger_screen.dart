import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/widgets/paged_list.dart';
import '../../core/widgets/states.dart';
import '../../l10n/app_localizations.dart';
import '../sales/sales_history_screen.dart' show SaleTile;
import '../sales/sales_models.dart';
import 'analytics_repository.dart';
import 'lens.dart';

/// Every sale behind a lens, newest first, cancelled ones included: what the numbers are made of.
/// Each opens the sale with its products, its corrections and who made them.
class LedgerScreen extends ConsumerStatefulWidget {
  const LedgerScreen({required this.lens, this.voidedOnly = false, super.key});

  final Lens lens;
  final bool voidedOnly;

  @override
  ConsumerState<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends ConsumerState<LedgerScreen> {
  late bool _voidedOnly = widget.voidedOnly;
  late PagedController<Sale> _sales = _controller();

  PagedController<Sale> _controller() => PagedController<Sale>((cursor) async {
    final page = await ref
        .read(analyticsRepositoryProvider)
        .sales(widget.lens, cursor: cursor, voidedOnly: _voidedOnly);
    return PageResult(page.items, page.nextCursor);
  });

  @override
  void dispose() {
    _sales.dispose();
    super.dispose();
  }

  void _toggle(bool voided) {
    if (voided == _voidedOnly) return;
    final old = _sales;
    setState(() {
      _voidedOnly = voided;
      _sales = _controller();
    });
    old.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.ledgerTitle)),
      body: PagedList<Sale>(
        key: ObjectKey(_sales),
        controller: _sales,
        header: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(t.ledgerAll),
                selected: !_voidedOnly,
                onSelected: (_) => _toggle(false),
              ),
              ChoiceChip(
                avatar: const Icon(LucideIcons.ban, size: 16),
                label: Text(t.ledgerVoidedOnly),
                selected: _voidedOnly,
                onSelected: (_) => _toggle(true),
              ),
            ],
          ),
        ),
        empty: EmptyState(icon: LucideIcons.receipt, title: t.noSalesInPeriod),
        itemBuilder: (context, sale, _) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SaleTile(sale: sale, showSeller: true, showDate: true),
        ),
      ),
    );
  }
}
