import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../data/services/local_database/database.dart';
import '../../../domain/models/models.dart';
import '../../../domain/models/money.dart';
import '../../core/design.dart';
import '../../core/forms.dart';
import '../authentication/session_view_model.dart';
import '../sales/sale_screen.dart';
import '../workspace/workspace_view_model.dart';

String operationLabel(String type) =>
    const {
      'sale.create': 'Vente',
      'sale.correct': 'Correction de vente',
      'sale.return': 'Retour client',
      'stock.receive': 'Entrée de stock',
      'stock.adjust': 'Inventaire',
      'stock.damage': 'Produits endommagés',
      'delivery.receive': 'Réception de livraison',
    }[type] ??
    'Opération du magasin';

class SyncScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  const SyncScreen({super.key, required this.vm});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool history = false, busy = false;
  String? error, storeId;
  Object? lastData;
  DateTime? syncedAt;
  int pending = -1;
  late Future<List<OutboxRow>> rows;

  @override
  void initState() {
    super.initState();
    reload();
    widget.vm.addListener(workspaceChanged);
  }

  void reload() {
    final state = widget.vm.state;
    storeId = state.store?.id;
    lastData = state.data;
    syncedAt = state.syncedAt;
    pending = state.pending;
    rows = storeId == null
        ? Future.value(<OutboxRow>[])
        : widget.vm.repository.operations(
            widget.vm.user.id,
            storeId!,
            includeResolved: history,
          );
  }

  void workspaceChanged() {
    final state = widget.vm.state;
    if (mounted &&
        (state.store?.id != storeId ||
            state.data != lastData ||
            state.syncedAt != syncedAt ||
            state.pending != pending)) {
      setState(reload);
    }
  }

  @override
  void dispose() {
    widget.vm.removeListener(workspaceChanged);
    super.dispose();
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          reload();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Synchronisation')),
    body: FutureBuilder<List<OutboxRow>>(
      future: rows,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final operations = loading
            ? <OutboxRow>[]
            : snapshot.data ?? <OutboxRow>[];
        return Content.builder(
          maxWidth: 760,
          itemCount: operations.length,
          itemBuilder: (context, index) {
            final row = operations[index];
            final command = Map<String, dynamic>.from(
              jsonDecode(row.payload)['command'],
            );
            final failed = ['conflict', 'rejected'].contains(row.status);
            final resolved = row.status == 'resolved';
            return CompactRow(
              title: operationLabel(command['type']),
              subtitle: dateLabel(row.createdAt.toIso8601String()),
              footer: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusChip(
                    resolved
                        ? 'Résolue'
                        : failed
                        ? 'À vérifier'
                        : row.status == 'accepted'
                        ? 'Confirmée · actualisation en cours'
                        : row.status == 'blocked'
                        ? 'Bloquée par une saisie précédente'
                        : row.status == 'retryable'
                        ? 'Nouvelle tentative programmée'
                        : 'En attente',
                    tone: failed
                        ? AppTone.danger
                        : resolved
                        ? AppTone.success
                        : AppTone.warning,
                    icon: failed
                        ? AppIcons.errorOutline
                        : resolved
                        ? AppIcons.checkCircleOutline
                        : AppIcons.schedule,
                  ),
                  Text(
                    row.resolution ??
                        row.error ??
                        'Conservée sur ce téléphone.',
                  ),
                  if (failed)
                    TextButton.icon(
                      onPressed: busy
                          ? null
                          : () => action(() => review(row, operations)),
                      icon: const Icon(AppIcons.rule),
                      label: const Text('Vérifier et résoudre'),
                    ),
                ],
              ),
            );
          },
          children: [
            const Notice(
              'Chaque opération conserve son compte et son magasin d’origine. Une erreur n’efface pas les informations enregistrées.',
            ),
            const SizedBox(height: 20),
            if (error != null) Notice(error!, error: true),
            FilledButton.icon(
              onPressed: busy ? null : () => action(widget.vm.synchronize),
              icon: const Icon(AppIcons.sync),
              label: const Text('Synchroniser maintenant'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: history,
              onChanged: (value) => setState(() {
                history = value;
                reload();
              }),
              title: const Text('Afficher les résolutions précédentes'),
            ),
            if (storeId == null)
              const Notice(
                'Sélectionnez un magasin pour consulter ses opérations.',
              )
            else if (snapshot.hasError)
              Notice(
                'Impossible de lire les opérations de ce téléphone.',
                error: true,
                retry: () => setState(reload),
              )
            else if (loading)
              const LinearProgressIndicator()
            else if (operations.isEmpty)
              EmptyState(
                title: history
                    ? 'Aucune opération enregistrée'
                    : 'Tout est synchronisé',
                description:
                    'Aucune opération ${history ? 'enregistrée' : 'en attente'} sur ce magasin.',
                icon: AppIcons.cloudDoneOutlined,
              ),
          ],
        );
      },
    ),
  );

  Future<void> review(OutboxRow row, List<OutboxRow> rows) async {
    final vm = widget.vm, store = widget.vm.state.store!;
    final command = Map<String, dynamic>.from(
      jsonDecode(row.payload)['command'],
    );
    final related = vm.repository.dependentOperations(rows, row.operationId);
    await vm.repository.refresh(vm.user, store);
    Json? serverSale;
    if (command['saleId'] != null) {
      try {
        final result = await vm.sales.details(store, command['saleId']);
        serverSale = Map<String, dynamic>.from(result['sale']);
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) rethrow;
      }
    }
    if (!mounted) return;
    final editable =
        ['sale.create', 'sale.correct'].contains(command['type']) &&
        related.every(
          (r) => [
            'sale.create',
            'sale.correct',
          ].contains(jsonDecode(r.payload)['command']['type']),
        );
    final decision = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vérifier la saisie'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.error ?? 'Cette saisie n’a pas été acceptée.'),
              const SizedBox(height: 12),
              if (serverSale != null)
                Text(
                  'Vente synchronisée : ${Money(integer(serverSale['totalMillimes'])).formatted} · révision ${serverSale['version']}.',
                ),
              if (related.length > 1)
                Text(
                  '${related.length} saisies liées seront traitées ensemble.',
                ),
              const SizedBox(height: 12),
              Text(
                editable
                    ? 'Reprenez les lignes enregistrées et vérifiez-les avant de confirmer. Vous pouvez aussi conserver les données du serveur.'
                    : 'Vérifiez les données actuelles du magasin. Conserver ces données retire les effets provisoires de cette saisie. Si nécessaire, enregistrez ensuite un nouveau retour, une réception ou un inventaire depuis son écran.',
              ),
              const Text(
                'La saisie d’origine et son motif de résolution restent conservés sur ce téléphone.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Plus tard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'server'),
            child: const Text('Conserver les données du serveur'),
          ),
          if (editable)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('Reprendre la vente'),
            ),
        ],
      ),
    );
    if (decision == null || !mounted) return;
    final ids = related.map((r) => r.operationId).toList();
    if (decision == 'server') {
      if (!await confirmAction(
        context,
        'Confirmer la résolution',
        'Les ${ids.length} saisie(s) sélectionnée(s) restent dans l’historique mais ne modifieront plus le stock ni les points.',
      )) {
        return;
      }
      await vm.repository.resolve(
        vm.user,
        store,
        ids,
        'Données synchronisées conservées après vérification.',
      );
      await vm.reloadLocal();
      await vm.synchronize();
    } else {
      final latest = Map<String, dynamic>.from(
        jsonDecode(related.last.payload)['command'],
      );
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SaleScreen(
            workspace: vm,
            original: serverSale,
            recovery: {
              'operationIds': ids,
              'saleId': command['saleId'],
              'occurredAt': command['occurredAt'],
              'lines': latest['lines'],
            },
          ),
        ),
      );
      await vm.reloadLocal();
    }
  }
}
