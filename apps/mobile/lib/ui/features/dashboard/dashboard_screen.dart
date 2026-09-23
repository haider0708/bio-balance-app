import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../domain/models/dashboard.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import '../workspace/workspace_view_model.dart';
import '../media/image_input.dart';
import 'dashboard_view_model.dart';
import '../workspace/workspace_help.dart';

enum DashboardDestination {
  sales,
  orders,
  deliveries,
  rewards,
  points,
  stock,
  expired,
  groups,
  stores,
  ranking,
}

class DashboardScreen extends StatelessWidget {
  final DashboardViewModel vm;
  final WorkspaceViewModel workspace;
  final String title, scopeLabel;
  final void Function(DashboardDestination, DashboardPeriod) onOpen;
  final void Function(String)? onComparison, onSale;
  final Widget? primaryAction, setup;
  const DashboardScreen({
    super.key,
    required this.vm,
    required this.workspace,
    required this.title,
    required this.scopeLabel,
    required this.onOpen,
    this.primaryAction,
    this.setup,
    this.onComparison,
    this.onSale,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) {
      final data = vm.data;
      return Content(
        key: PageStorageKey(
          'dashboard:${vm.scope}:${vm.groupId}:${vm.storeId}',
        ),
        children: [
          SectionTitle(
            title,
            subtitle: scopeLabel,
            action: IconButton(
              onPressed: vm.loading ? null : () => vm.load(),
              tooltip: 'Actualiser',
              icon: const Icon(AppIcons.refresh),
            ),
          ),
          if (primaryAction != null) ...[
            primaryAction!,
            const SizedBox(height: 20),
          ],

          Row(
            children: [
              Expanded(
                child: PopupMenuButton<DashboardPeriod>(
                  tooltip: 'Période des ventes',
                  onSelected: (period) => vm.load(period),
                  itemBuilder: (_) => [
                    for (final period in [
                      DashboardPeriod.today(),
                      DashboardPeriod.week(),
                      DashboardPeriod.month(),
                    ])
                      PopupMenuItem(value: period, child: Text(period.label)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        const Icon(
                          AppIcons.calendar,
                          size: 18,
                          color: darkGreen,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            vm.period.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(AppIcons.keyboardArrowDown, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => chooseDates(context),
                child: const Text('Dates'),
              ),
            ],
          ),
          Text(
            '${TunisDates.dateOnlyLabel(vm.period.from)} – ${TunisDates.dateOnlyLabel(vm.period.to)}',
            style: const TextStyle(fontSize: 14, color: muted),
          ),
          const SizedBox(height: 12),
          if (vm.loading) const LinearProgressIndicator(minHeight: 2),
          if (vm.error != null) Notice(vm.error!, retry: () => vm.load()),
          if (data != null) ...[
            Text(
              '${data.cached ? 'Hors connexion · données enregistrées' : 'Données synchronisées'} · ${TunisDates.timestampLabel(data.raw['generatedAt'])}',
              style: const TextStyle(fontSize: 14, color: muted),
            ),
            const SizedBox(height: 12),
            _metrics([
              (
                'Ventes nettes',
                Money(data.netMillimes).formatted,
                DashboardDestination.sales,
              ),
              ('Unités nettes', '${data.netUnits}', DashboardDestination.sales),
              (
                'Ventes enregistrées',
                '${data.saleCount}',
                DashboardDestination.sales,
              ),
            ]),
            if (setup != null) ...[const SizedBox(height: 16), setup!],
            if (vm.scope == 'personal') ...[
              const SizedBox(height: 12),
              _metrics([
                (
                  'Points disponibles',
                  '${data.current['availablePoints']}',
                  DashboardDestination.points,
                ),
                (
                  'Points réservés',
                  '${data.current['reservedPoints']}',
                  DashboardDestination.points,
                ),
              ]),
              for (final sale in data.list('recentSales'))
                CompactRow(
                  title: Money(integer(sale['netMillimes'])).formatted,
                  subtitle:
                      '${TunisDates.timestampLabel(sale['occurredAt'])} · ${sale['netUnits']} unités nettes',
                  onTap: onSale == null ? null : () => onSale!(sale['id']),
                ),
              CompactRow(
                title: 'Mes dernières ventes',
                subtitle: 'Historique, corrections et retours',
                icon: AppIcons.receiptLongOutlined,
                onTap: () => onOpen(DashboardDestination.sales, vm.period),
              ),
              CompactRow(
                title: 'Classement de ce mois',
                subtitle: data.raw['ranking']?['rank'] == null
                    ? 'Votre première vente synchronisée vous inscrit au classement.'
                    : '${data.raw['ranking']['rank']}ᵉ · ${data.raw['ranking']['score']} points gagnés nets',
                icon: AppIcons.trophy,
                onTap: () => onOpen(DashboardDestination.ranking, vm.period),
              ),
            ],
            if (vm.storeId != null)
              FirstUseHint(
                key: ValueKey('tips:${vm.storeId}'),
                workspace: workspace,
                storeId: vm.storeId!,
              ),
            const SizedBox(height: 20),
            const SectionTitle(
              'Évolution des ventes',
              subtitle: 'Retours déduits de la période de vente initiale',
            ),
            if (data.list('series').isEmpty)
              const CompactRow(
                title: 'Aucune vente sur cette période',
                subtitle: 'Les ventes synchronisées apparaîtront ici.',
                icon: AppIcons.receiptLongOutlined,
              )
            else
              _Trend(data.list('series'), vm.period),
            if (data.list('comparisons').length > 1) ...[
              const SizedBox(height: 20),
              SectionTitle(
                vm.scope == 'network'
                    ? 'Contribution des groupes'
                    : 'Comparaison des magasins',
                subtitle: 'Ventes nettes · 20 premiers',
              ),
              for (final item in data.list('comparisons'))
                CompactRow(
                  title: item['name'],
                  value: Money(integer(item['netMillimes'])).formatted,
                  onTap: onComparison == null
                      ? null
                      : () => onComparison!(item['id']),
                ),
            ],
            if (data.list('products').isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionTitle('Produits les plus vendus'),
              for (final item in data.list('products'))
                CompactRow(
                  title: item['name'],
                  subtitle: '${item['netUnits']} unités nettes',
                  value: Money(integer(item['netMillimes'])).formatted,
                  leading: SizedBox(
                    width: 48,
                    height: 56,
                    child: item['imageId'] == null
                        ? const Icon(AppIcons.photo, color: muted)
                        : ProtectedImage(
                            vm: workspace,
                            id: item['imageId'],
                            height: 56,
                          ),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            const SectionTitle(
              'Situation actuelle',
              subtitle: 'Indépendante de la période sélectionnée',
            ),
            if (vm.scope == 'network')
              _metrics([
                (
                  'Groupes',
                  '${data.raw['groupCount']}',
                  DashboardDestination.groups,
                ),
                (
                  'Magasins',
                  '${data.raw['storeCount']}',
                  DashboardDestination.stores,
                ),
              ]),
            if (vm.scope != 'personal')
              _metrics([
                (
                  'Commandes en cours',
                  '${data.current['pendingOrders']}',
                  DashboardDestination.orders,
                ),
                (
                  'Stocks faibles',
                  '${data.current['lowStock']}',
                  DashboardDestination.stock,
                ),
                (
                  'Lots expirés',
                  '${data.current['expiredLots']}',
                  DashboardDestination.expired,
                ),
              ]),
            CompactRow(
              title: 'Livraisons à réceptionner',
              value: '${data.current['pendingDeliveries']}',
              icon: AppIcons.package,
              onTap: () => onOpen(DashboardDestination.deliveries, vm.period),
            ),
            CompactRow(
              title: 'Demandes de récompense',
              value: '${data.current['pendingClaims']}',
              icon: AppIcons.redeemOutlined,
              onTap: () => onOpen(DashboardDestination.rewards, vm.period),
            ),

            if (data.list('alerts').isNotEmpty) ...[
              const SizedBox(height: 20),
              const SectionTitle('À vérifier'),
              for (final alert in data.list('alerts'))
                CompactRow(
                  title: alert['message'],
                  subtitle: alert['storeName'],
                  icon: AppIcons.infoOutline,
                  tone: AppTone.warning,
                  onTap: onComparison == null
                      ? () => onOpen(DashboardDestination.stock, vm.period)
                      : () => onComparison!(alert['storeId']),
                ),
            ],
          ],
        ],
      );
    },
  );
  Widget _metrics(
    List<(String, String, DashboardDestination)> items,
  ) => LayoutBuilder(
    builder: (context, c) {
      final columns =
          MediaQuery.textScalerOf(context).scale(16) > 23 || c.maxWidth < 280
          ? 1
          : c.maxWidth < 650
          ? 2
          : 3;
      final width = (c.maxWidth - (columns - 1) * 8) / columns;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final item in items)
            SizedBox(
              width: items.length.isOdd && item == items.first
                  ? c.maxWidth
                  : width,
              child: Material(
                color: const Color(0xFFF1F8F4),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => onOpen(item.$3, vm.period),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: const TextStyle(fontSize: 14, color: muted),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
  Future<void> chooseDates(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(
        start: DateTime.parse(vm.period.from),
        end: DateTime.parse(vm.period.to),
      ),
      helpText: 'Période des ventes · 366 jours maximum',
    );
    if (range == null || !context.mounted) return;
    if (range.duration.inDays >= 366) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choisissez une période de 366 jours maximum.'),
        ),
      );
      return;
    }
    await vm.load(
      DashboardPeriod(
        TunisDates.civil(range.start),
        TunisDates.civil(range.end),
        'Période personnalisée',
      ),
    );
  }
}

class _Trend extends StatelessWidget {
  final List<Json> series;
  final DashboardPeriod period;
  const _Trend(this.series, this.period);
  @override
  Widget build(BuildContext context) {
    final byDay = {
      for (final s in series) s['day']: integer(s['netMillimes']) / 1000,
    };
    final start = DateTime.parse(period.from),
        days = DateTime.parse(period.to)
            .difference(DateTime.parse(period.from))
            .inDays;
    final points = [
      for (var i = 0; i <= days; i++)
        FlSpot(
          i.toDouble(),
          byDay[TunisDates.civil(start.add(Duration(days: i)))] ?? 0,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: days == 0 ? 1 : days.toDouble(),
                minY: 0,
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: points,
                    isCurved: false,
                    color: darkGreen,
                    barWidth: 2,
                    dotData: FlDotData(show: points.length == 1),
                    belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFFF1F8F4),
                    ),
                  ),
                ],
              ),
              duration: Duration.zero,
            ),
          ),
        ),
        ExpansionTile(
          key: PageStorageKey('trend-values:${period.key}'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Voir les valeurs', style: TextStyle(fontSize: 14)),
          children: [
            for (final s in series)
              CompactRow(
                title: TunisDates.dateOnlyLabel(s['day']),
                value: Money(integer(s['netMillimes'])).formatted,
              ),
          ],
        ),
      ],
    );
  }
}
