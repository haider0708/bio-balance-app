import 'report_export_control.dart';

import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../../core/formatting.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class HistoryScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  final String resource, title;
  final String? productId;
  const HistoryScreen({
    super.key,
    required this.vm,
    required this.resource,
    required this.title,
    this.productId,
  });
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final items = <Json>[];
  final people = <String, String>{};
  late final Store store;
  String? cursor, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    store = widget.vm.state.store!;
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.vm.reporting.history(
        store,
        widget.resource,
        productId: widget.productId,
        before: cursor,
      );
      if (mounted) {
        setState(() {
          items.addAll(objects(result['items']));
          cursor = result['nextCursor'];
          error = null;
          for (final p in objects(result['people'])) {
            people[p['id']] = p['name'];
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: Column(
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Notice(error!, retry: load),
          ),
        if (items.isNotEmpty &&
            (store.canManage || widget.resource == 'points'))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ReportExportControl(
              workspace: widget.vm,
              query: {
                'kind': 'history',
                'resource': widget.resource,
                'organizationId': store.organizationId,
                'storeId': store.id,
                if (widget.productId != null) 'productId': widget.productId,
              },
            ),
          ),
        Expanded(
          child: items.isEmpty && !busy
              ? const EmptyState(
                  title: 'Aucun mouvement',
                  description:
                      'L’historique apparaîtra après les premières opérations.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length + 1,
                  itemBuilder: (context, i) {
                    if (i == items.length) {
                      return busy
                          ? const Center(child: CircularProgressIndicator())
                          : cursor == null
                          ? const SizedBox.shrink()
                          : OutlinedButton(
                              onPressed: load,
                              child: const Text(
                                'Charger les opérations précédentes',
                              ),
                            );
                    }
                    final r = items[i];
                    final value = r['totalMillimes'] != null
                        ? Money(integer(r['totalMillimes'])).formatted
                        : r['amount'] != null
                        ? '${r['amount']} points'
                        : r['quantity'] != null
                        ? '${r['quantity']} unités'
                        : r['action'] ?? 'Opération';
                    return CompactRow(
                      title: value,
                      subtitle:
                          '${dateLabel(r['occurredAt'] ?? r['createdAt'])} · ${people[r['actorId'] ?? r['sellerId'] ?? r['userId']] ?? ''}\n${r['reason'] ?? (r['kind'] == 'redemption'
                                  ? 'Récompense remise'
                                  : r['kind'] == 'earned'
                                  ? 'Vente, correction ou retour'
                                  : '')}',
                    );
                  },
                ),
        ),
      ],
    ),
  );
}
