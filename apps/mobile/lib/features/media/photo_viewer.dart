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

/// Several photos full screen: swipe between them, pinch to zoom.
class PhotoGalleryScreen extends StatefulWidget {
  const PhotoGalleryScreen({required this.ids, this.initial = 0, super.key});

  final List<String> ids;
  final int initial;

  @override
  State<PhotoGalleryScreen> createState() => _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  late final PageController _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_index + 1} / ${widget.ids.length}',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: widget.ids.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: AuthImage(widget.ids[i], radius: 0, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
