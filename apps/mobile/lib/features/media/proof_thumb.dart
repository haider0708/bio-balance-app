import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/files/files.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/feedback.dart';
import '../../l10n/app_localizations.dart';
import 'media_repository.dart';

/// A proof on the server: its photo, or a document card for a PDF.
class ProofThumb extends ConsumerWidget {
  const ProofThumb(
    this.id, {
    required this.width,
    required this.height,
    this.radius = 14,
    super.key,
  });

  final String id;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(mediaInfoProvider(id)).value;
    if (info?.isDocument ?? false) {
      return DocumentCard(
        name: info!.fileName,
        width: width,
        height: height,
        radius: radius,
      );
    }
    return AuthImage(id, width: width, height: height, radius: radius);
  }
}

/// How a document looks among photos: a page icon, "PDF" and its name.
class DocumentCard extends StatelessWidget {
  const DocumentCard({
    required this.name,
    required this.width,
    required this.height,
    this.radius = 14,
    super.key,
  });

  final String name;
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${AppLocalizations.of(context).documentLabel}: $name',
    child: Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.status.infoSoft,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: context.status.info.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.fileText,
            size: height > 150 ? 44 : 30,
            color: context.status.info,
          ),
          const SizedBox(height: 6),
          Text(
            'PDF',
            style: context.text.labelLarge?.copyWith(
              color: context.status.info,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          if (name.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(
                color: context.status.muted,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Opens a proof: a document in the phone's viewer (a new tab on the web), photos in the gallery.
Future<void> openProof(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
  int index,
) async {
  final id = ids[index];
  final info = await ref
      .read(mediaInfoProvider(id).future)
      .catchError(
        (Object _) => const MediaInfo(mime: 'image/jpeg', fileName: ''),
      );
  if (!context.mounted) return;
  if (info.isDocument) {
    await perform(context, () async {
      final bytes = await ref.read(mediaRepositoryProvider).bytes(id);
      await viewFile(
        info.fileName.toLowerCase().endsWith('.pdf')
            ? info.fileName
            : 'biobalance-$id.pdf',
        bytes,
        'application/pdf',
      );
    });
    return;
  }
  // The gallery swipes through the photos only: what each file is, known for all of them first.
  final kinds = await Future.wait([
    for (final other in ids)
      ref
          .read(mediaInfoProvider(other).future)
          .then((i) => i.isDocument, onError: (Object _) => false),
  ]);
  if (!context.mounted) return;
  final photos = [
    for (var i = 0; i < ids.length; i++)
      if (!kinds[i]) ids[i],
  ];
  await context.push('/photos', extra: (photos, photos.indexOf(id)));
}
