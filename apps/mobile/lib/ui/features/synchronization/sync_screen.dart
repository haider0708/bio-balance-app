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
  int pending = -1, revision = -1;
  bool syncing = false;
  String? syncError;
  late Future<List<OutboxRow>> rows;

  @override
  void initState() {
    super.initState();
    widget.vm.observeSynchronization();
    reload();
    widget.vm.addListener(workspaceChanged);
  }

  void reload() {
    final state = widget.vm.state;
    storeId = state.store?.id;
    lastData = state.data;
    syncedAt = state.syncedAt;
    pending = state.pending;
    revision = widget.vm.syncRevision;
    syncing = state.syncing;
    syncError = state.syncError;
    rows = widget.vm.repository.accountOperations(
      widget.vm.user.id,
      includeResolved: history,
    );
  }

  void workspaceChanged() {
    final state = widget.vm.state;
    if (mounted &&
        (state.store?.id != storeId ||
            state.data != lastData ||
            state.syncedAt != syncedAt ||
            state.pending != pending ||
            widget.vm.syncRevision != revision ||
            state.syncing != syncing ||
            state.syncError != syncError)) {
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
            final store = widget.vm.state.stores
                .where((s) => s.id == row.storeId)
                .firstOrNull;
            return CompactRow(
              title: operationLabel(command['type']),
              subtitle:
                  '${store == null ? 'Magasin inaccessible · ${row.storeId}' : '${store.organizationName} · ${store.name}'}\n${dateLabel(row.createdAt.toIso8601String())}',
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
                  if (!resolved && store == null)
                    const Text(
                      'Votre accès à ce magasin doit être rétabli avant de poursuivre. La saisie reste conservée.',
                    ),
                  if (row.nextAttemptAt != null && row.status == 'retryable')
                    Text(
                      row.nextAttemptAt!.isAfter(DateTime.now())
                          ? 'Nouvelle tentative à ${dateLabel(row.nextAttemptAt!.toIso8601String())}, si l’application est ouverte et connectée.'
                          : 'La prochaine synchronisation réessaiera cette saisie.',
                    ),
                  if (row.status == 'blocked')
                    const Text(
                      'Vérifiez d’abord la saisie précédente de ce magasin. Les autres magasins continuent à se synchroniser.',
                    ),
                  if (failed && store != null)
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
            const SectionTitle(
              'Sur ce téléphone',
              subtitle: 'Tous les magasins de votre compte',
            ),
            const Text(
              'Vos saisies sont envoyées automatiquement quand l’application est ouverte et connectée, même si vous changez de magasin. Une erreur ne les efface pas.',
            ),
            const SizedBox(height: 20),
            if (error != null) Notice(error!, error: true),
            if (widget.vm.state.syncError != null)
              Notice(widget.vm.state.syncError!, error: true),
            if (widget.vm.api.accessBlocked)
              const Notice(
                'Reconnectez-vous avec ce compte pour reprendre la synchronisation. Vos saisies restent conservées.',
              ),
            FilledButton.icon(
              onPressed:
                  busy || widget.vm.state.syncing || widget.vm.api.accessBlocked
                  ? null
                  : () => action(widget.vm.synchronize),
              icon: const Icon(AppIcons.sync),
              label: Text(
                busy || widget.vm.state.syncing
                    ? 'Synchronisation en cours…'
                    : 'Synchroniser maintenant',
              ),
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
            if (snapshot.hasError)
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
                    'Aucune opération ${history ? 'enregistrée' : 'en attente'} pour votre compte sur ce téléphone.',
                icon: AppIcons.cloudDoneOutlined,
              ),
          ],
        );
      },
    ),
  );

  Future<void> review(OutboxRow row, List<OutboxRow> rows) async {
    final vm = widget.vm;
    final store = vm.state.stores.where((s) => s.id == row.storeId).firstOrNull;
    if (store == null) {
      throw const AppFailure(
        'STORE_ACCESS_REVOKED',
        'Votre accès à ce magasin doit être rétabli.',
      );
    }
    vm.requireAccess(store);
    final command = Map<String, dynamic>.from(
      jsonDecode(row.payload)['command'],
    );
    final related = vm.repository.dependentOperations(
      rows.where((r) => r.storeId == row.storeId).toList(),
      row.operationId,
    );
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
        vm.state.store?.id == store.id &&
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
              Text('${store.organizationName} · ${store.name}'),
              if (vm.state.store?.id != store.id &&
                  ['sale.create', 'sale.correct'].contains(command['type']))
                Text(
                  'Pour reprendre la vente, ouvrez ${store.name} depuis son groupe puis revenez à cette saisie.',
                ),
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
      if (vm.state.store?.id != store.id) {
        throw const AppFailure(
          'STORE_CHANGED',
          'Le magasin a changé. Ouvrez le magasin de cette saisie avant de reprendre la vente.',
        );
      }
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
