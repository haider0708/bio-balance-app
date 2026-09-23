import 'report_export_control.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/dashboard_repository.dart';
import '../../../domain/models/dashboard.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../../domain/models/tunis_dates.dart';
import '../../core/design.dart';
import '../authentication/session_view_model.dart';
import '../sales/sales_history_screen.dart';
import '../workspace/workspace_view_model.dart';
import '../workspace/operation_helpers.dart';

class ScopedSalesViewModel extends ChangeNotifier {
  final WorkspaceViewModel workspace;
  final String scope;
  final String? groupId, storeId;
  final DashboardPeriod period;
  late final repository = DashboardRepository(
    workspace.repositoryContext,
    workspace.repository,
    workspace.user.id,
  );
  List<Json> items = [];
  String? after, error;
  bool loading = false, closed = false;
  ScopedSalesViewModel(
    this.workspace,
    this.scope,
    this.period,
    this.groupId,
    this.storeId,
  );
  Future<void> load({bool more = false}) async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final data = await repository.sales(
        scope,
        period,
        organizationId: groupId,
        storeId: storeId,
        after: more ? after : null,
      );
      if (closed) return;
      items = [if (more) ...items, ...objects(data['items'])];
      after = data['nextCursor'];
      error = null;
    } catch (e) {
      if (!closed) error = SessionViewModel.message(e);
    } finally {
      if (!closed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

class ScopedSalesScreen extends StatefulWidget {
  final WorkspaceViewModel workspace;
  final String scope, title;
  final String? groupId, storeId;
  final DashboardPeriod period;
  const ScopedSalesScreen({
    super.key,
    required this.workspace,
    required this.scope,
    required this.title,
    required this.period,
    this.groupId,
    this.storeId,
  });
  @override
  State<ScopedSalesScreen> createState() => _ScopedSalesScreenState();
}

class _ScopedSalesScreenState extends State<ScopedSalesScreen> {
  late final vm = ScopedSalesViewModel(
    widget.workspace,
    widget.scope,
    widget.period,
    widget.groupId,
    widget.storeId,
  )..load();
  bool opening = false;
  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Ventes enregistrées')),
      body: Content.builder(
        itemCount: vm.items.length,
        itemBuilder: (_, i) {
          final sale = vm.items[i];
          return CompactRow(
            title: Money(integer(sale['netMillimes'])).formatted,
            subtitle:
                '${sale['storeName']} · ${sale['sellerName']}\n${TunisDates.timestampLabel(sale['occurredAt'])} · ${sale['netUnits']} unités nettes',
            onTap: opening ? null : () => openSale(sale),
          );
        },
        children: [
          SectionTitle(
            widget.title,
            subtitle:
                '${TunisDates.dateOnlyLabel(widget.period.from)} – ${TunisDates.dateOnlyLabel(widget.period.to)} · retours déduits',
          ),
          if (vm.error != null) Notice(vm.error!, retry: () => vm.load()),
          if (vm.loading) const LinearProgressIndicator(),
          ReportExportControl(
            workspace: widget.workspace,
            query: {
              'scope': widget.scope,
              'from': widget.period.from,
              'to': widget.period.to,
              if (widget.groupId != null) 'organizationId': widget.groupId,
              if (widget.storeId != null) 'storeId': widget.storeId,
            },
          ),
          if (vm.after != null)
            TextButton(
              onPressed: vm.loading ? null : () => vm.load(more: true),
              child: const Text('Charger les ventes suivantes'),
            ),
          if (vm.items.isEmpty && !vm.loading)
            const EmptyState(
              title: 'Aucune vente sur cette période',
              description: 'Modifiez les dates depuis le tableau de bord.',
            ),
        ],
      ),
    ),
  );
  Future<void> openSale(Json sale) async {
    if (opening) return;
    setState(() => opening = true);
    await run(context, () async {
      final store = widget.workspace.state.stores
          .where(
            (s) =>
                s.id == sale['storeId'] &&
                s.organizationId == sale['organizationId'],
          )
          .firstOrNull;
      if (store == null) {
        throw const AppFailure('STORE_ACCESS_REVOKED', 'Magasin inaccessible.');
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScopedSaleScreen(
            parent: widget.workspace,
            store: store,
            id: sale['id'],
          ),
        ),
      );
      await widget.workspace.reloadLocal();
      await vm.load();
    });
    if (mounted) setState(() => opening = false);
  }
}

class ScopedSaleScreen extends StatefulWidget {
  final WorkspaceViewModel parent;
  final Store store;
  final String id;
  const ScopedSaleScreen({
    super.key,
    required this.parent,
    required this.store,
    required this.id,
  });
  @override
  State<ScopedSaleScreen> createState() => _ScopedSaleState();
}

class _ScopedSaleState extends State<ScopedSaleScreen> {
  late final workspace = WorkspaceViewModel(
    widget.parent.user,
    widget.parent.repository,
    widget.parent.api,
  );
  late final detach = widget.parent.registerDraft(workspace.flushDrafts);
  Json? sale;
  String? error;
  int accessRevision = 0;
  @override
  void initState() {
    super.initState();
    detach;
    workspace.addListener(access);
    load();
  }

  void access() {
    if (workspace.accessRevision != accessRevision) {
      accessRevision = workspace.accessRevision;
      unawaited(
        widget.parent.closeProtectedRoutes().catchError((Object e) {
          if (mounted) setState(() => error = SessionViewModel.message(e));
        }),
      );
    }
  }

  Future<void> load() async {
    try {
      await workspace.select(widget.store);
      final result = await workspace.sales.details(widget.store, widget.id);
      if (mounted) {
        setState(() => sale = Map<String, dynamic>.from(result['sale']));
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }
  }

  @override
  void dispose() {
    detach();
    workspace.removeListener(access);
    workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: workspace,
    child: sale == null
        ? Scaffold(
            appBar: AppBar(title: Text(widget.store.name)),
            body: error == null
                ? const Center(child: CircularProgressIndicator())
                : Content(children: [Notice(error!, retry: load)]),
          )
        : SaleDetailScreen(vm: workspace, sale: sale!),
  );
}
