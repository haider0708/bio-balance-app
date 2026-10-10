import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../features/media/media_repository.dart';
import '../../l10n/app_localizations.dart';
import '../config.dart';
import '../theme/app_theme.dart';
import 'components.dart';
import 'feedback.dart';

/// Take (or choose) a photo, upload it right away, and report its id.
/// Used for the proof photos: stock declarations and delivery papers.
class PhotoField extends ConsumerStatefulWidget {
  const PhotoField({
    required this.onChanged,
    required this.label,
    this.purpose = 'PROOF',
    this.initialId,
    super.key,
  });

  final ValueChanged<String?> onChanged;
  final String label;
  final String purpose;
  final String? initialId;

  @override
  ConsumerState<PhotoField> createState() => _PhotoFieldState();
}

class _PhotoFieldState extends ConsumerState<PhotoField> {
  Uint8List? _preview;
  String? _id;
  bool _uploading = false;

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: AppConfig.photoMaxWidth,
      imageQuality: AppConfig.photoQuality,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _preview = bytes;
      _uploading = true;
      _id = null;
    });
    widget.onChanged(null);
    try {
      final id = await ref
          .read(mediaRepositoryProvider)
          .upload(bytes, purpose: widget.purpose);
      if (!mounted) return;
      setState(() => _id = id);
      widget.onChanged(id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _preview = null);
      showError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _choose() async {
    final t = AppLocalizations.of(context);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.camera),
              title: Text(t.photoTake),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(LucideIcons.image),
              title: Text(t.photoChoose),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const Gap(8),
          ],
        ),
      ),
    );
    if (source != null) await _pick(source);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final hasPhoto = _preview != null || widget.initialId != null;
    return Semantics(
      button: true,
      label: widget.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _uploading ? null : _choose,
        child: Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _id != null
                  ? context.status.success
                  : context.colors.outlineVariant,
              width: _id != null ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_preview != null) Image.memory(_preview!, fit: BoxFit.cover),
              if (_preview == null && widget.initialId != null)
                AuthImage(widget.initialId, radius: 0),
              if (!hasPhoto)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.camera,
                      size: 36,
                      color: context.colors.primary,
                    ),
                    const Gap(10),
                    Text(widget.label, style: context.text.titleSmall),
                    const Gap(2),
                    Text(
                      t.photoHint,
                      style: context.text.bodySmall?.copyWith(
                        color: context.status.muted,
                      ),
                    ),
                  ],
                ),
              if (_uploading)
                ColoredBox(
                  color: Colors.black45,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const Gap(10),
                        Text(
                          t.photoUploading,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              if (hasPhoto && !_uploading)
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: StatusChip(
                    _id != null ? t.photoReady : t.photoRetake,
                    tone: _id != null ? Tone.success : Tone.muted,
                    icon: _id != null
                        ? LucideIcons.check
                        : LucideIcons.refreshCw,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
