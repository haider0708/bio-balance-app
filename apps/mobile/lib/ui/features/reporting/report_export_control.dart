import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/export_repository.dart';
import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class ReportExportViewModel extends ChangeNotifier {
  final WorkspaceViewModel workspace;
  final Json query;
  late final repository = ExportRepository(workspace.repositoryContext);
  late final key =
      'report-export:${jsonEncode(SplayTreeMap<String, dynamic>.from(query))}';
  final cancel = CancelToken();
  String? id, error;
  Json? result;
  bool busy = false, closed = false;
  ReportExportViewModel(this.workspace, this.query);

  Future<void> refresh({bool create = false, bool restart = false}) async {
    if (busy || closed) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      if (restart) {
        id = null;
        result = null;
      } else {
        id ??= (await workspace.repository.draft(
          workspace.user.id,
          '',
          key,
        ))?['id'];
      }
      if (create) {
        id ??= const Uuid().v4();
        await workspace.repository.saveDraft(workspace.user.id, '', key, {
          'id': id,
        });
        result = await repository.create(id!, query);
      } else if (id != null) {
        result = await repository.status(id!);
      }
    } catch (e) {
      if (e is DioException && [404, 410].contains(e.response?.statusCode)) {
        id = null;
        result = null;
        try {
          await workspace.repository.saveDraft(workspace.user.id, '', key, {});
        } catch (storageError) {
          error = SessionViewModel.message(storageError);
          return;
        }
      }
      error = SessionViewModel.message(e);
    } finally {
      busy = false;
      if (!closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    closed = true;
    cancel.cancel('Export screen closed');
    super.dispose();
  }
}

class ReportExportControl extends StatefulWidget {
  final WorkspaceViewModel workspace;
  final Json query;
  const ReportExportControl({
    super.key,
    required this.workspace,
    required this.query,
  });
  @override
  State<ReportExportControl> createState() => _ReportExportControlState();
}

class _ReportExportControlState extends State<ReportExportControl> {
  late final vm = ReportExportViewModel(widget.workspace, widget.query)
    ..refresh();
  bool sharing = false;
  String? error;
  @override
  void dispose() {
    vm.dispose();
    super.dispose();
  }

  Future<void> share() async {
    if (sharing || vm.id == null) return;
    setState(() {
      sharing = true;
      error = null;
    });
    try {
      final file = await vm.repository.download(vm.id!, vm.cancel);
      if (!mounted) return;
      widget.workspace.repositoryContext.check();
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          title: 'Export BioBalance',
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: vm,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if ((error ?? vm.error) != null) Notice((error ?? vm.error)!),
        if (vm.result == null)
          OutlinedButton.icon(
            onPressed: vm.busy ? null : () => vm.refresh(create: true),
            icon: const Icon(AppIcons.download),
            label: const Text('Exporter toutes les lignes filtrées'),
          )
        else ...[
          Text(switch (vm.result!['status']) {
            'ready' => 'Export prêt · ${vm.result!['rows']} lignes',
            'failed' => 'La préparation a échoué. Vous pouvez réessayer.',
            _ => 'Préparation du fichier en arrière-plan…',
          }),
          if (vm.result!['status'] == 'ready') ...[
            OutlinedButton.icon(
              onPressed: sharing ? null : share,
              icon: const Icon(AppIcons.download),
              label: Text(
                sharing ? 'Téléchargement…' : 'Enregistrer le fichier CSV',
              ),
            ),
            TextButton(
              onPressed: vm.busy || sharing
                  ? null
                  : () => vm.refresh(create: true, restart: true),
              child: const Text('Actualiser l’export'),
            ),
          ] else if (vm.result!['status'] == 'failed')
            TextButton(
              onPressed: vm.busy
                  ? null
                  : () => vm.refresh(create: true, restart: true),
              child: const Text('Créer un nouvel export'),
            )
          else
            TextButton(
              onPressed: vm.busy ? null : () => vm.refresh(),
              child: const Text('Vérifier la préparation'),
            ),
        ],
      ],
    ),
  );
}
