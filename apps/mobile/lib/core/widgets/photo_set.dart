import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/media/media_repository.dart';
import '../../features/media/proof_thumb.dart';
import '../../l10n/app_localizations.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import 'components.dart';
import 'feedback.dart';

enum _Upload { sending, done, failed }

enum _Source { camera, gallery, document }

class _Shot {
  _Shot(this.bytes, {this.document}) : state = _Upload.sending;

  /// A file that is already on the server (editing something that has proofs).
  _Shot.saved(String this.id)
    : bytes = null,
      document = null,
      state = _Upload.done;

  final Uint8List? bytes;

  /// The file name when this is a document (a PDF) rather than a photo.
  final String? document;
  _Upload state;
  String? id;
}

/// The largest document the server takes as proof.
const _maxDocumentBytes = 12 * 1024 * 1024;

/// One to five proofs, photos or documents: take a photo, choose photos, or choose a PDF (a
/// delivery note, an invoice). Photos are shrunk on the phone; files are uploaded two at a time
/// in the background and can be retried or removed. Reports the ids that are ready (in the
/// order shown) and whether anything is still uploading.
class PhotoSet extends ConsumerStatefulWidget {
  const PhotoSet({
    required this.onChanged,
    required this.label,
    this.max = 5,
    this.initialIds = const [],
    super.key,
  });

  final void Function(List<String> ids, bool busy) onChanged;
  final String label;
  final int max;

  /// Photos that are already saved: shown first, and kept unless removed.
  final List<String> initialIds;

  @override
  ConsumerState<PhotoSet> createState() => _PhotoSetState();
}

class _PhotoSetState extends ConsumerState<PhotoSet> {
  late final List<_Shot> _shots = [
    for (final id in widget.initialIds) _Shot.saved(id),
  ];
  int _running = 0;
  final List<_Shot> _queue = [];

  void _report() {
    widget.onChanged([
      for (final s in _shots)
        if (s.state == _Upload.done) s.id!,
    ], _shots.any((s) => s.state == _Upload.sending));
  }

  void _pump() {
    while (_running < 2 && _queue.isNotEmpty) {
      final shot = _queue.removeAt(0);
      _running++;
      unawaited(_upload(shot));
    }
  }

  Future<void> _upload(_Shot shot) async {
    try {
      final id = await ref
          .read(mediaRepositoryProvider)
          .upload(
            shot.bytes!,
            purpose: 'PROOF',
            filename: shot.document ?? 'photo.jpg',
          );
      shot
        ..id = id
        ..state = _Upload.done;
    } catch (_) {
      shot.state = _Upload.failed;
    } finally {
      _running--;
      if (mounted) {
        setState(() {});
        _report();
        _pump();
      }
    }
  }

  void _add(Uint8List bytes, {String? document}) {
    final shot = _Shot(bytes, document: document);
    setState(() => _shots.add(shot));
    _queue.add(shot);
    _report();
    _pump();
  }

  Future<void> _take() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: AppConfig.photoMaxWidth,
      imageQuality: AppConfig.photoQuality,
    );
    if (picked != null) _add(await picked.readAsBytes());
  }

  Future<void> _choose() async {
    final room = widget.max - _shots.length;
    final picked = await ImagePicker().pickMultiImage(
      maxWidth: AppConfig.photoMaxWidth,
      imageQuality: AppConfig.photoQuality,
      limit: room < 2 ? 2 : room,
    );
    for (final file in picked.take(room)) {
      _add(await file.readAsBytes());
    }
  }

  Future<void> _document() async {
    final t = AppLocalizations.of(context);
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    if (bytes.length > _maxDocumentBytes) {
      showMessage(context, t.documentTooLarge, error: true);
      return;
    }
    _add(bytes, document: picked.name);
  }

  Future<void> _addMenu() async {
    final t = AppLocalizations.of(context);
    final choice = await showModalBottomSheet<_Source>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: Text(t.photoTake),
              onTap: () => Navigator.pop(context, _Source.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.images),
              title: Text(t.photoChoose),
              onTap: () => Navigator.pop(context, _Source.gallery),
            ),
            ListTile(
              leading: const Icon(LucideIcons.fileText),
              title: Text(t.photoChooseDocument),
              subtitle: Text(t.photoChooseDocumentHint),
              onTap: () => Navigator.pop(context, _Source.document),
            ),
            const Gap(8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      await switch (choice) {
        _Source.camera => _take(),
        _Source.gallery => _choose(),
        _Source.document => _document(),
      };
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  void _remove(_Shot shot) {
    _queue.remove(shot);
    setState(() => _shots.remove(shot));
    _report();
  }

  void _retry(_Shot shot) {
    setState(() => shot.state = _Upload.sending);
    _queue.add(shot);
    _report();
    _pump();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final full = _shots.length >= widget.max;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final shot in _shots)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: _Thumb(
                    shot: shot,
                    onRemove: () => _remove(shot),
                    onRetry: () => _retry(shot),
                  ),
                ),
              if (!full)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _addMenu,
                  child: Container(
                    width: _shots.isEmpty ? 220 : 112,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.colors.outlineVariant),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _shots.isEmpty
                              ? LucideIcons.camera
                              : LucideIcons.plus,
                          size: 30,
                          color: context.colors.primary,
                        ),
                        const Gap(6),
                        Text(
                          _shots.isEmpty ? widget.label : t.photoAddAnother,
                          textAlign: TextAlign.center,
                          style: context.text.labelLarge,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Gap(6),
        Text(
          t.photoCount(
            _shots.where((s) => s.state == _Upload.done).length,
            widget.max,
          ),
          style: context.text.bodySmall?.copyWith(color: context.status.muted),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.shot,
    required this.onRemove,
    required this.onRetry,
  });

  final _Shot shot;
  final VoidCallback onRemove;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return SizedBox(
      width: 112,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: shot.bytes == null
                ? ProofThumb(shot.id!, width: 112, height: 112, radius: 0)
                : shot.document != null
                ? DocumentCard(
                    name: shot.document!,
                    width: 112,
                    height: 112,
                    radius: 0,
                  )
                : Image.memory(shot.bytes!, fit: BoxFit.cover, cacheWidth: 300),
          ),
          if (shot.state == _Upload.sending)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: const ColoredBox(
                color: Colors.black45,
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          if (shot.state == _Upload.failed)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    label: Text(t.retry),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                  ),
                ),
              ),
            ),
          if (shot.state == _Upload.done)
            Positioned(
              left: 6,
              bottom: 6,
              child: Icon(
                LucideIcons.circleCheck,
                size: 20,
                color: context.status.success,
              ),
            ),
          Positioned(
            right: 4,
            top: 4,
            child: InkResponse(
              onTap: onRemove,
              child: const CircleAvatar(
                radius: 12,
                backgroundColor: Colors.black54,
                child: Icon(LucideIcons.x, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The proofs of a count or a delivery, side by side: tap a photo to swipe through the photos
/// full screen, a document to open it.
class PhotoStrip extends ConsumerWidget {
  const PhotoStrip({required this.ids, super.key});

  final List<String> ids;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ids.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: ids.length == 1 ? 200 : 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: ids.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => openProof(context, ref, ids, i),
          child: ProofThumb(
            ids[i],
            width: ids.length == 1 ? 300 : 130,
            height: ids.length == 1 ? 200 : 130,
          ),
        ),
      ),
    );
  }
}
