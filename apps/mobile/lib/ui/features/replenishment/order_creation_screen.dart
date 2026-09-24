import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';
import 'order_screens.dart';

/// Store changes save the old draft without changing the workspace behind this route.
class OrderCreationScreen extends StatefulWidget {
  final WorkspaceViewModel parent;
  final String? groupId;
  final Store? initialStore;
  const OrderCreationScreen({
    super.key,
    required this.parent,
    this.groupId,
    this.initialStore,
  });
  @override
  State<OrderCreationScreen> createState() => _OrderCreationScreenState();
}

class _OrderCreationScreenState extends State<OrderCreationScreen> {
  late final workspace = WorkspaceViewModel(
    widget.parent.user,
    widget.parent.repository,
    widget.parent.api,
  );
  late final detach = widget.parent.registerDraft(workspace.flushDrafts);
  Store? selected;
  bool switching = false;
  String? error;
  int accessRevision = 0;
  int selectorRevision = 0;
  List<Store> get stores => widget.parent.state.stores
      .where(
        (store) =>
            (widget.groupId == null ||
                store.organizationId == widget.groupId) &&
            store.status == 'active' &&
            (store.canManage || widget.parent.user.admin),
      )
      .toList();
  @override
  void initState() {
    super.initState();
    detach;
    workspace.addListener(accessChanged);
    final initial =
        widget.initialStore ?? (stores.length == 1 ? stores.single : null);
    if (initial != null &&
        stores.any(
          (store) =>
              store.id == initial.id &&
              store.organizationId == initial.organizationId,
        )) {
      unawaited(select(initial));
    }
  }

  void accessChanged() {
    if (workspace.accessRevision == accessRevision) return;
    accessRevision = workspace.accessRevision;
    unawaited(
      widget.parent.closeProtectedRoutes().catchError((Object e) {
        if (mounted) setState(() => error = SessionViewModel.message(e));
      }),
    );
  }

  Future<void> select(Store store) async {
    if (switching || selected?.id == store.id) return;
    setState(() {
      switching = true;
      error = null;
      selectorRevision++;
    });
    try {
      widget.parent.requireAccess(store, 'manage');
      await workspace.flushDrafts();
      if (!mounted) return;
      setState(() => selected = null);
      await workspace.select(store, rememberSelection: false);
      if (!mounted) return;
      workspace.requireAccess(store, 'manage');
      if (workspace.state.data == null) {
        throw AppFailure(
          'STORE_NOT_CACHED',
          workspace.state.error ?? 'Connectez-vous pour télécharger les produits de ce magasin. Vos brouillons sont conservés.',
        );
      }
      setState(() => selected = store);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => switching = false);
    }
  }

  Widget selector() => DropdownButtonFormField<String>(
    key: ValueKey('order.store:${selected?.id ?? 'none'}:$selectorRevision'),
    initialValue: selected?.id,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Magasin à approvisionner'),
    items: [
      for (final store in stores)
        DropdownMenuItem(
          value: store.id,
          child: Text(
            widget.groupId == null
                ? '${store.organizationName} · ${store.name}'
                : store.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: switching
        ? null
        : (id) {
            final store = stores.where((store) => store.id == id).firstOrNull;
            if (store != null) unawaited(select(store));
          },
  );
  @override
  void dispose() {
    workspace.removeListener(accessChanged);
    detach();
    workspace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider.value(
    value: workspace,
    child: AbsorbPointer(
      absorbing: switching,
      child: selected == null
          ? FormPage(
              title: 'Nouvelle commande',
              children: [
                selector(),
                const SizedBox(height: 16),
                const Text(
                  'Choisissez le magasin, puis les produits et les quantités à demander à BioBalance.',
                ),
                if (switching) const LinearProgressIndicator(),
                if (error != null) Notice(error!, error: true),
                if (stores.isEmpty)
                  const Notice(
                    'Créez ou réactivez un magasin avant de passer une commande.',
                  ),
              ],
            )
          : OrderEditor(
              key: ValueKey(selected!.id),
              vm: workspace,
              storeSelector: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  selector(),
                  if (switching) const LinearProgressIndicator(),
                  if (error != null) Notice(error!, error: true),
                ],
              ),
            ),
    ),
  );
}
