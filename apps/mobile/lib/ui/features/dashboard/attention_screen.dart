import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/dashboard_repository.dart';
import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../authentication/session_view_model.dart';
import '../inventory/inventory_screens.dart';
import '../rewards/rewards_screen.dart';
import '../workspace/operation_helpers.dart';
import '../workspace/workspace_view_model.dart';

class AttentionViewModel extends ChangeNotifier {
  final DashboardRepository repository;
  final String scope, kind;
  final String? groupId, storeId;
  List<Json> items = [];
  String? after, error;
  bool loading = false, closed = false;
  AttentionViewModel(
    this.repository,
    this.scope,
    this.kind,
    this.groupId,
    this.storeId,
  );
  Future<void> load({bool more = false}) async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      final page = await repository.attention(
        scope,
        kind,
        organizationId: groupId,
        storeId: storeId,
        after: more ? after : null,
      );
      if (!closed) {
        items = [if (more) ...items, ...objects(page['items'])];
        after = page['nextCursor'];
        error = null;
      }
    } catch (e) {
      if (!closed) error = SessionViewModel.message(e);
    } finally {
      loading = false;
      if (!closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

class AttentionScreen extends StatefulWidget {
  final WorkspaceViewModel workspace;
  final String scope, kind, title, scopeLabel;
  final String? groupId, storeId;
  const AttentionScreen({
    super.key,
    required this.workspace,
    required this.scope,
    required this.kind,
    required this.title,
    required this.scopeLabel,
    this.groupId,
    this.storeId,
  });
  @override
  State<AttentionScreen> createState() => _AttentionScreenState();
}

class _AttentionScreenState extends State<AttentionScreen> {
  late final vm = AttentionViewModel(
    DashboardRepository(
      widget.workspace.repositoryContext,
      widget.workspace.repository,
      widget.workspace.user.id,
    ),
    widget.scope,
    widget.kind,
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: ListenableBuilder(
      listenable: vm,
      builder: (context, _) => Content.builder(
        itemCount: vm.items.length + (vm.after == null ? 0 : 1),
        itemBuilder: (context, i) {
          if (i == vm.items.length) {
            return OutlinedButton(
              onPressed: vm.loading ? null : () => vm.load(more: true),
              child: const Text('Charger la suite'),
            );
          }
          final item = vm.items[i];
          return CompactRow(
            title: item['title'],
            subtitle: '${item['storeName']} · ${item['detail']}',
            onTap: opening ? null : () => open(item),
          );
        },
        children: [
          SectionTitle(widget.scopeLabel, subtitle: 'Situation actuelle'),
          if (vm.loading) const LinearProgressIndicator(),
          if (vm.error != null) Notice(vm.error!, retry: () => vm.load()),
          if (!vm.loading && vm.items.isEmpty)
            const EmptyState(
              title: 'Tout est à jour',
              description: 'Aucun élément à traiter dans cet espace.',
            ),
        ],
      ),
    ),
  );
  Future<void> open(Json item) async {
    if (opening) return;
    setState(() => opening = true);
    await run(context, () async {
      final store = widget.workspace.state.stores
          .where(
            (s) =>
                s.id == item['storeId'] &&
                s.organizationId == item['organizationId'],
          )
          .firstOrNull;
      if (store == null) {
        throw const AppFailure('STORE_ACCESS_REVOKED', 'Magasin inaccessible.');
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _AttentionDetail(
            parent: widget.workspace,
            store: store,
            item: item,
          ),
        ),
      );
      await widget.workspace.reloadLocal();
      if (mounted) await vm.load();
    });
    if (mounted) setState(() => opening = false);
  }
}

class _AttentionDetail extends StatefulWidget {
  final WorkspaceViewModel parent;
  final Store store;
  final Json item;
  const _AttentionDetail({
    required this.parent,
    required this.store,
    required this.item,
  });
  @override
  State<_AttentionDetail> createState() => _AttentionDetailState();
}

class _AttentionDetailState extends State<_AttentionDetail> {
  late final vm = WorkspaceViewModel(
    widget.parent.user,
    widget.parent.repository,
    widget.parent.api,
  );
  late final detach = widget.parent.registerDraft(vm.flushDrafts);
  String? error;
  int accessRevision = 0;
  @override
  void initState() {
    super.initState();
    detach;
    vm.addListener(changed);
    load();
  }

  void changed() {
    if (vm.accessRevision != accessRevision) {
      accessRevision = vm.accessRevision;
      unawaited(
        widget.parent.closeProtectedRoutes().catchError((Object e) {
          if (mounted) setState(() => error = SessionViewModel.message(e));
        }),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    try {
      await vm.select(widget.store);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }
  }

  @override
  void dispose() {
    detach();
    vm.removeListener(changed);
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget page;
    final data = vm.state.data, kind = widget.item['kind'];
    if (data == null || vm.state.accessBlocked) {
      page = Scaffold(
        appBar: AppBar(title: Text(widget.store.name)),
        body: Content(
          children: [
            if (vm.state.loading) const LinearProgressIndicator(),
            Notice(
              error ?? vm.state.error ?? 'Chargement du magasin…',
              retry: load,
            ),
          ],
        ),
      );
    } else if (kind == 'deliveries') {
      final delivery = data
          .list('deliveries')
          .where((d) => d['id'] == widget.item['id'])
          .firstOrNull;
      page = delivery == null
          ? Scaffold(
              appBar: AppBar(title: Text(widget.store.name)),
              body: const Content(
                children: [Notice('Cette livraison a déjà été réceptionnée.')],
              ),
            )
          : ReceiptScreen(vm: vm, delivery: delivery);
    } else if (kind == 'rewards') {
      page = Scaffold(
        appBar: AppBar(title: Text(widget.store.name)),
        body: RewardsPage(vm: vm, claimId: widget.item['id']),
      );
    } else {
      final product = data.products
          .where((p) => p.id == widget.item['productId'])
          .firstOrNull;
      page = product == null
          ? Scaffold(
              appBar: AppBar(title: Text(widget.store.name)),
              body: StockPage(vm: vm),
            )
          : ProductDetail(vm: vm, product: product);
    }
    return ChangeNotifierProvider.value(value: vm, child: page);
  }
}
