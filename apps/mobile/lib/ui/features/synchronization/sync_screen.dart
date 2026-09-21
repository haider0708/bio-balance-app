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
  String? error;
  Future<void> action(Future<void> Function() work) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Synchronisation')),
    body: Content(
      maxWidth: 760,
      children: [
        const Notice(
          'Chaque opération conserve son compte et son magasin d’origine. Une erreur n’efface pas les informations enregistrées.',
        ),
        const SizedBox(height: 20),
        if (error != null) Notice(error!, error: true),
        FilledButton.icon(
          onPressed: busy ? null : () => action(widget.vm.synchronize),
          icon: const Icon(Icons.sync),
          label: const Text('Synchroniser maintenant'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: history,
          onChanged: (v) => setState(() => history = v),
          title: const Text('Afficher les résolutions précédentes'),
        ),
        if (widget.vm.state.store == null)
          const Notice('Sélectionnez un magasin pour consulter ses opérations.')
        else
          FutureBuilder(
            future: widget.vm.repository.operations(
              widget.vm.user.id,
              widget.vm.state.store!.id,
              includeResolved: history,
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Notice(
                  'Impossible de lire les opérations de ce téléphone.',
                  error: true,
                );
              }
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final rows = snapshot.data!;
              if (rows.isEmpty) {
                return const EmptyState(
                  title: 'Tout est synchronisé',
                  description: 'Aucune opération en attente sur ce magasin.',
                  icon: Icons.cloud_done_outlined,
                );
              }
              return Column(
                children: rows.map((r) {
                  final command = Map<String, dynamic>.from(
                    jsonDecode(r.payload)['command'],
                  );
                  final failed = ['conflict', 'rejected'].contains(r.status);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            operationLabel(command['type']),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(dateLabel(r.createdAt.toIso8601String())),
                          StatusChip(
                            r.status == 'resolved'
                                ? 'Résolue'
                                : failed
                                ? 'À vérifier'
                                : r.status == 'accepted'
                                ? 'Confirmée · actualisation en cours'
                                : 'En attente',
                          ),
                          Text(
                            r.resolution ??
                                r.error ??
                                'Conservée sur ce téléphone.',
                          ),
                          if (failed)
                            TextButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => action(() => review(r, rows)),
                              icon: const Icon(Icons.rule),
                              label: const Text('Vérifier et résoudre'),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    ),
  );

  Future<void> review(OutboxRow row, List<OutboxRow> rows) async {
    final vm = widget.vm, store = widget.vm.state.store!;
    final command = Map<String, dynamic>.from(
      jsonDecode(row.payload)['command'],
    );
    // Later commands for the same entity were created from this provisional
    // state. They must be reviewed together before that state is replaced.
    final key = [
      'saleId',
      'deliveryId',
      'lotId',
    ].where(command.containsKey).firstOrNull;
    final related = rows.where((r) {
      if (r.status == 'resolved' || r.sequence < row.sequence) return false;
      if (r.operationId == row.operationId) return true;
      final c = jsonDecode(r.payload)['command'];
      return key != null && c[key] == command[key];
    }).toList();
    await vm.repository.refresh(vm.user, store);
    Json? serverSale;
    if (command['saleId'] != null) {
      try {
        final result = await vm.api.request(
          'GET',
          '/v1/stores/${store.id}/sales/${command['saleId']}',
          query: {'organizationId': store.organizationId},
        );
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
