import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../data/repositories/media_upload_repository.dart';
import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class ImageInput extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Store? store;
  final String purpose, label;
  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<bool>? onBusyChanged;
  const ImageInput({
    super.key,
    required this.vm,
    required this.store,
    required this.purpose,
    required this.label,
    required this.controller,
    this.enabled = true,
    this.onBusyChanged,
  });
  @override
  State<ImageInput> createState() => _ImageInputState();
}

class _ImageInputState extends State<ImageInput> {
  late final repository = MediaUploadRepository(
    widget.vm.repository,
    widget.vm.api,
  );
  final cancel = CancelToken();
  bool busy = false;
  double? progress;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    cancel.cancel();
    widget.controller.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
      if (widget.controller.text.isNotEmpty) ...[
        const SizedBox(height: 12),
        ProtectedImage(vm: widget.vm, id: widget.controller.text, height: 140),
      ],
      if (error != null) Notice(error!, error: true),
      if (busy) ...[
        LinearProgressIndicator(value: progress),
        const Text('Téléversement et traitement de l’image…'),
      ],
      Wrap(
        spacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: busy || !widget.enabled ? null : choose,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              widget.controller.text.isEmpty
                  ? 'Choisir une image'
                  : 'Remplacer l’image',
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            TextButton(
              onPressed: busy || !widget.enabled
                  ? null
                  : () => widget.controller.clear(),
              child: const Text('Retirer l’image'),
            ),
        ],
      ),
      const Text(
        'JPEG ou PNG · 10 Mo maximum',
        style: TextStyle(fontSize: 14, color: muted),
      ),
    ],
  );
  Future<void> choose() async {
    final binding = widget.vm.api.binding;
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
    );
    if (!mounted || selected.isEmpty || selected.single.path == null) return;
    widget.onBusyChanged?.call(true);
    setState(() {
      busy = true;
      progress = null;
      error = null;
    });
    try {
      widget.vm.api.requireBinding(binding);
      final file = selected.single;
      var asset = await repository.upload(
        accountId: widget.vm.user.id,
        file: File(file.path!),
        name: file.name,
        mime: file.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : 'image/jpeg',
        purpose: widget.purpose,
        store: widget.store,
        cancel: cancel,
        progress: (v) {
          if (mounted) setState(() => progress = v);
        },
      );
      for (
        var attempt = 0;
        asset['status'] == 'processing' && attempt < 30;
        attempt++
      ) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        widget.vm.api.requireBinding(binding);
        if (cancel.isCancelled) throw cancel.cancelError!;
        asset = await repository.status(asset['id']);
      }
      if (asset['status'] != 'ready') {
        throw const AppFailure(
          'MEDIA_PROCESSING',
          'Le traitement n’est pas terminé. Choisissez le même fichier pour reprendre la vérification.',
        );
      }
      if (mounted) widget.controller.text = asset['id'];
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        widget.onBusyChanged?.call(false);
      }
    }
  }
}

class ProtectedImage extends StatelessWidget {
  final WorkspaceViewModel vm;
  final String id;
  final double height;
  const ProtectedImage({
    super.key,
    required this.vm,
    required this.id,
    this.height = 120,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.network(
      vm.api.mediaUri(id, vm.api.binding).toString(),
      headers: {'Authorization': vm.api.binding.authorization ?? ''},
      height: height,
      cacheHeight: (height * MediaQuery.devicePixelRatioOf(context))
          .ceil()
          .clamp(1, 1024),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const Icon(Icons.image_not_supported_outlined),
      loadingBuilder: (_, child, event) => event == null
          ? child
          : SizedBox(
              height: height,
              child: const Center(child: CircularProgressIndicator()),
            ),
    ),
  );
}
