import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/json.dart';
import '../../core/auth/session.dart';
import '../../core/theme/app_theme.dart';

class MediaRepository {
  MediaRepository(this._ref);

  final Ref _ref;

  /// Upload a file. `purpose` is PROOF (photos of stock and delivery papers), PRODUCT or TRAINING.
  Future<String> upload(Uint8List bytes, {required String purpose, String filename = 'photo.jpg'}) async {
    final response = await _ref.read(apiClientProvider).upload(
      '/v1/media',
      bytes,
      query: {'purpose': purpose, 'filename': filename},
    ) as Json;
    return response.str('id');
  }

  Future<Uint8List> bytes(String id) async =>
      Uint8List.fromList(await _ref.read(apiClientProvider).bytes('/v1/media/$id'));

  Future<void> download(String id, String path) =>
      _ref.read(apiClientProvider).download('/v1/media/$id', path);
}

final mediaRepositoryProvider = Provider<MediaRepository>(MediaRepository.new);

/// Image bytes by id, kept in memory while the app runs.
final mediaBytesProvider = FutureProvider.family<Uint8List, String>(
  (ref, id) => ref.watch(mediaRepositoryProvider).bytes(id),
);

/// An image stored on the server (they need the sign-in token, so a plain network image won't do).
class AuthImage extends ConsumerWidget {
  const AuthImage(
    this.mediaId, {
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.radius = 12,
    this.placeholderIcon = LucideIcons.image,
    super.key,
  });

  final String? mediaId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double radius;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(placeholderIcon, color: context.status.muted, size: (width ?? 48) * 0.4),
    );
    final id = mediaId;
    if (id == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ref.watch(mediaBytesProvider(id)).when(
            data: (bytes) => Image.memory(bytes, width: width, height: height, fit: fit, gaplessPlayback: true),
            loading: () => placeholder,
            error: (_, _) => placeholder,
          ),
    );
  }
}
