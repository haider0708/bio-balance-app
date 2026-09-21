import '../../core/navigation.dart';

import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../workspace/workspace_view_model.dart';
import '../authentication/session_view_model.dart';

class CatalogImportScreen extends StatefulWidget {
  final WorkspaceViewModel vm;
  const CatalogImportScreen({super.key, required this.vm});
  @override
  State<CatalogImportScreen> createState() => _CatalogImportScreenState();
}

class _CatalogImportScreenState extends State<CatalogImportScreen> {
  List<Json> rows = [];
  String? error;
  bool valid = false, busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Importer le catalogue')),
    body: Content(
      maxWidth: 900,
      children: [
        const Notice(
          'CSV UTF-8 avec les colonnes reference, name et barcode (facultatif). Les doublons sont refusés. Le fichier est vérifié avant toute création.',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: busy ? null : choose,
          icon: const Icon(Icons.upload_file),
          label: const Text('Choisir un fichier CSV'),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Notice(error!, error: true),
        ],
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 20),
          SectionTitle(
            '${rows.length} produits à importer',
            subtitle: 'Vérifiez l’aperçu avant de confirmer.',
          ),
          ...rows
              .take(30)
              .map(
                (r) => ListTile(
                  title: Text(r['name']),
                  subtitle: Text(
                    '${r['reference']} · ${r['barcode'] ?? 'Sans code-barres'}',
                  ),
                ),
              ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: valid && !busy ? commit : null,
            child: Text(
              busy ? 'Veuillez patienter…' : 'Confirmer l’importation',
            ),
          ),
        ],
      ],
    ),
  );
  Future<void> choose() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (file?.path == null) return;
    setState(() {
      busy = true;
      valid = false;
      error = null;
    });
    try {
      final data = await File(file!.path!).readAsString();
      if (data.length > 1000000) {
        throw const FormatException('Le fichier dépasse 1 Mo.');
      }
      final records = Csv().decode(data);
      if (records.length < 2 || records.length > 1001) {
        throw const FormatException(
          'Le fichier doit contenir de 1 à 1 000 produits.',
        );
      }
      final headers = records.first
          .map((v) => v.toString().trim().replaceAll('\uFEFF', ''))
          .toList();
      if (!headers.contains('reference') || !headers.contains('name')) {
        throw const FormatException('Colonnes reference et name requises.');
      }
      final parsed = records.skip(1).map((r) {
        if (r.length != headers.length) {
          throw const FormatException(
            'Une ligne comporte un nombre incorrect de colonnes.',
          );
        }
        final row = {
          for (var i = 0; i < headers.length; i++)
            headers[i]: r[i].toString().trim(),
        };
        return <String, dynamic>{
          'reference': row['reference'],
          'name': row['name'],
          if (row['barcode']?.isNotEmpty ?? false) 'barcode': row['barcode'],
          'description': row['description'] ?? '',
          'active': true,
        };
      }).toList();
      await widget.vm.catalog.importRows(parsed, commit: false);
      if (mounted) {
        setState(() {
          rows = parsed;
          valid = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> commit() async {
    setState(() => busy = true);
    try {
      await widget.vm.catalog.importRows(rows, commit: true);
      await widget.vm.synchronize();
      if (mounted) completeRoute(context);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}
