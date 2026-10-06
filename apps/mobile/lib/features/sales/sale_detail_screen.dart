import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/auth/me.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/dates.dart';
import '../../core/util/money.dart';
import '../../core/widgets/async_body.dart';
import '../../core/widgets/components.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/quantity_editor.dart';
import '../../l10n/app_localizations.dart';
import '../media/media_repository.dart';
import 'sales_models.dart';
import 'sales_repository.dart';

class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({required this.saleId, super.key});

  final String saleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final sale = ref.watch(saleProvider(saleId));
    return Scaffold(
      appBar: AppBar(title: Text(t.saleDetailTitle)),
      body: AsyncBody(
        value: sale,
        onRetry: () => ref.invalidate(saleProvider(saleId)),
        builder: (sale) {
          final canCorrect = !sale.voided && (me.role != Role.vendeur || sale.sellerCanCorrect);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(Dates.dateTime(sale.occurredAt, t.localeName), style: context.text.titleMedium)),
                        if (sale.voided) StatusChip(t.saleVoided, tone: Tone.muted) else if (sale.version > 1) StatusChip(t.corrected, tone: Tone.info),
                      ],
                    ),
                    const Gap(12),
                    if (me.role != Role.vendeur) ...[InfoRow(t.seller, sale.seller.name), InfoRow(t.pointOfSale, sale.pdv.name)],
                    InfoRow(t.totalUnits, t.units(sale.units)),
                    InfoRow(t.reward, sale.voided ? '—' : Money.format(sale.rewardMillimes, t.localeName)),
                  ],
                ),
              ),
              SectionHeader(t.products),
              for (final line in sale.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        AuthImage(line.imageId, width: 48, height: 48, radius: 10, placeholderIcon: LucideIcons.package),
                        const SizedBox(width: 12),
                        Expanded(child: Text(line.name, style: context.text.titleSmall)),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('× ${line.quantity}', style: context.text.titleSmall),
                            if (line.rewardMillimes > 0) Text('+ ${Money.format(line.rewardMillimes, t.localeName)}', style: context.text.bodySmall?.copyWith(color: context.colors.primary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (sale.revisions.isNotEmpty) ...[
                SectionHeader(t.corrections),
                for (final r in sale.revisions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(LucideIcons.pencilLine, color: context.status.info),
                    title: Text(r.reason),
                    subtitle: Text(Dates.dateTime(r.createdAt, t.localeName)),
                  ),
              ],
              const Gap(24),
              if (canCorrect) OutlinedButton.icon(onPressed: () => context.push('/sales/${sale.id}/correct', extra: sale), icon: const Icon(LucideIcons.pencil), label: Text(t.correctSale)),
              if (me.role == Role.vendeur && !sale.voided && !sale.sellerCanCorrect) Text(t.correctionWindowClosed, style: context.text.bodySmall?.copyWith(color: context.status.muted), textAlign: TextAlign.center),
            ],
          );
        },
      ),
    );
  }
}

/// Change the quantities of a sale, or cancel it entirely. A reason is always kept.
class CorrectSaleScreen extends ConsumerStatefulWidget {
  const CorrectSaleScreen({required this.sale, super.key});

  final Sale sale;

  @override
  ConsumerState<CorrectSaleScreen> createState() => _CorrectSaleScreenState();
}

class _CorrectSaleScreenState extends ConsumerState<CorrectSaleScreen> {
  late final QuantityController _quantities = QuantityController([
    for (final l in widget.sale.lines) QuantityItem(productId: l.productId, name: l.name, family: '', quantity: l.quantity, imageId: l.imageId),
  ]);
  final _reason = TextEditingController();

  @override
  void dispose() {
    _quantities.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context);
    final lines = _quantities.lines(skipZero: true);
    final cancelling = lines.isEmpty;
    if (cancelling && !await confirm(context, title: t.cancelSaleTitle, message: t.cancelSaleBody, confirmLabel: t.cancelSale, destructive: true)) return;
    if (!mounted) return;
    final ok = await perform(
      context,
      () => ref.read(salesRepositoryProvider).correct(widget.sale.id, reason: _reason.text.trim(), lines: lines),
      success: cancelling ? t.saleCancelled : t.saleCorrected,
    );
    if (ok && mounted) {
      ref.invalidate(saleProvider(widget.sale.id));
      context.pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.correctSale)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t.correctSaleHint, style: context.text.bodyMedium?.copyWith(color: context.status.muted)),
          const Gap(16),
          QuantityEditor(controller: _quantities, allowAdd: false, allowRemove: false),
          const Gap(16),
          TextField(
            controller: _reason,
            minLines: 2,
            maxLines: 3,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: t.reasonRequired),
            onChanged: (_) => setState(() {}),
          ),
          const Gap(8),
          ListenableBuilder(
            listenable: _quantities,
            builder: (context, _) => AsyncButton(
              label: _quantities.total == 0 ? t.cancelSale : t.saveCorrection,
              style: _quantities.total == 0 ? AsyncButtonStyle.danger : AsyncButtonStyle.filled,
              onPressed: _reason.text.trim().length < 2 ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
