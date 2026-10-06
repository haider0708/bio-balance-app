import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'media_repository.dart';

/// A photo full screen, zoomable.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({required this.mediaId, super.key});

  final String mediaId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          AppLocalizations.of(context).photo,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: AuthImage(mediaId, radius: 0, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
