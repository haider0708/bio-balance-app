import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../domain/models/models.dart';
import '../../core/design.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

class TrainingPage extends StatefulWidget {
  final WorkspaceViewModel vm;
  const TrainingPage({super.key, required this.vm});
  @override
  State<TrainingPage> createState() => _TrainingPageState();
}

class _TrainingPageState extends State<TrainingPage> {
  List<Json> articles = [];
  bool loading = true;
  String query = '';
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final vm = widget.vm;
    final cached = await vm.repository.draft(vm.user.id, '', 'training');
    if (mounted && cached != null) {
      setState(() => articles = objects(cached['items']));
    }
    try {
      final items = objects(await vm.request('GET', '/v1/training'));
      await vm.repository.saveDraft(vm.user.id, '', 'training', {
        'items': items,
      });
      if (mounted) {
        setState(() {
          articles = items;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = articles
        .where(
          (a) =>
              a['title'].toString().toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return Content(
      children: [
        SectionTitle(
          'La connaissance fait la différence',
          subtitle: 'Vos produits, leurs bénéfices et les bons conseils pour les présenter.',
          action: widget.vm.user.admin
              ? FilledButton.icon(
                  onPressed: () => edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Créer un contenu'),
                )
              : null,
        ),
        TextField(
          onChanged: (s) => setState(() => query = s),
          decoration: const InputDecoration(
            hintText: 'Rechercher une formation',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 20),
        if (error != null) ...[
          Notice(error!, retry: load),
          const SizedBox(height: 16),
        ],
        if (loading && articles.isEmpty)
          const Center(child: CircularProgressIndicator()),
        if (!loading && items.isEmpty)
          const EmptyState(
            title: 'Aucune formation à afficher',
            description: 'Les articles et vidéos publiés par BioBalance apparaîtront ici.',
            icon: Icons.school_outlined,
          ),
        ...items.map(
          (article) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TrainingReader(vm: widget.vm, article: article),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        article['type'] == 'video'
                            ? Icons.play_circle_outline
                            : Icons.menu_book_outlined,
                        color: darkGreen,
                        size: 36,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        article['title'],
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      StatusChip(
                        '${article['type'] == 'video' ? 'Vidéo' : 'Article'}${widget.vm.user.admin ? ' · ${article['status']}' : ''}',
                        icon: Icons.school_outlined,
                      ),
                      if (widget.vm.user.admin)
                        TextButton(
                          onPressed: () => edit(article),
                          child: const Text('Modifier / publier'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> edit([Json? article]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrainingEditor(vm: widget.vm, article: article),
      ),
    );
    await load();
  }
}

class TrainingEditor extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Json? article;
  const TrainingEditor({super.key, required this.vm, this.article});
  @override
  State<TrainingEditor> createState() => _TrainingEditorState();
}

class _TrainingEditorState extends State<TrainingEditor> {
  late final TextEditingController title, body;
  String type = 'article', status = 'draft';
  String? mediaId, error;
  double? progress;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.article?['title'] ?? '');
    body = TextEditingController(text: widget.article?['body'] ?? '');
    type = widget.article?['type'] ?? 'article';
    status = widget.article?['status'] ?? 'draft';
    mediaId = widget.article?['mediaId'];
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Éditer une formation')),
    body: Content(
      maxWidth: 760,
      children: [
        if (error != null) ...[
          Notice(error!, error: true),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Titre'),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: body,
          minLines: 8,
          maxLines: 20,
          decoration: const InputDecoration(
            labelText: 'Article ou description',
          ),
        ),
        const SizedBox(height: 20),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'article', label: Text('Article')),
            ButtonSegment(value: 'video', label: Text('Vidéo')),
          ],
          selected: {type},
          onSelectionChanged: (v) => setState(() => type = v.single),
        ),
        if (type == 'video') ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: busy ? null : upload,
            icon: const Icon(Icons.upload_file),
            label: Text(
              mediaId == null
                  ? 'Choisir une vidéo'
                  : 'Remplacer / reprendre une vidéo',
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            Text('${(progress! * 100).round()} % téléversé'),
          ],
          if (mediaId != null)
            TextButton(
              onPressed: checkMedia,
              child: const Text('Vérifier le traitement du média'),
            ),
        ],
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: status,
          items: const [
            DropdownMenuItem(value: 'draft', child: Text('Brouillon')),
            DropdownMenuItem(value: 'published', child: Text('Publié')),
            DropdownMenuItem(value: 'archived', child: Text('Archivé')),
          ],
          onChanged: (v) => setState(() => status = v!),
          decoration: const InputDecoration(labelText: 'Visibilité'),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: busy ? null : save,
          child: const Text('Enregistrer le contenu'),
        ),
      ],
    ),
  );
  Future<void> checkMedia() async {
    try {
      final asset = await widget.vm.request(
        'GET',
        '/v1/media/uploads/$mediaId',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('État du média : ${asset['status']}')),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }
  }

  Future<void> upload() async {
    final chosen = await FilePicker.pickFiles(type: FileType.video);
    final filePath = chosen.isEmpty ? null : chosen.single.path;
    if (filePath == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final vm = widget.vm,
          file = File(filePath),
          size = await File(filePath).length();
      final cached = await vm.repository.draft(
        vm.user.id,
        '',
        'upload:$filePath',
      );
      Json asset;
      if (cached != null && cached['size'] == size) {
        asset = Map<String, dynamic>.from(
          await vm.request('GET', '/v1/media/uploads/${cached['id']}'),
        );
      } else {
        asset = Map<String, dynamic>.from(
          await vm.request(
            'POST',
            '/v1/media/uploads',
            body: {
              'fileName': chosen.single.name,
              'mime': filePath.toLowerCase().endsWith('.mov')
                  ? 'video/quicktime'
                  : 'video/mp4',
              'size': size,
            },
          ),
        );
        await vm.repository.saveDraft(vm.user.id, '', 'upload:$filePath', {
          'id': asset['id'],
          'size': size,
        });
      }
      mediaId = asset['id'];
      var offset = integer(asset['received']);
      final handle = await file.open();
      try {
        while (offset < size) {
          await handle.setPosition(offset);
          final chunk = await handle.read(4 * 1024 * 1024);
          final response = await vm.api.http.put(
            '/v1/media/uploads/$mediaId',
            data: Stream.value(chunk),
            options: Options(
              headers: {
                'Content-Type': 'application/octet-stream',
                'Upload-Offset': '$offset',
                'Content-Length': '${chunk.length}',
              },
            ),
          );
          offset = integer(response.data['received']);
          if (mounted) setState(() => progress = offset / size);
        }
      } finally {
        await handle.close();
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.vm.repository.saveDraft(
        widget.vm.user.id,
        '',
        'training:${widget.article?['id'] ?? 'new'}',
        {
          'title': title.text,
          'body': body.text,
          'mediaId': mediaId,
          'type': type,
          'status': status,
        },
      );
      await widget.vm.request(
        'POST',
        '/v1/training',
        body: {
          if (widget.article != null) 'id': widget.article!['id'],
          if (widget.article != null)
            'expectedVersion': widget.article!['version'],
          'title': title.text,
          'body': body.text,
          'type': type,
          'status': status,
          if (mediaId != null) 'mediaId': mediaId,
          'productIds': widget.article?['productIds'] ?? [],
        },
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class TrainingReader extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Json article;
  const TrainingReader({super.key, required this.vm, required this.article});
  @override
  State<TrainingReader> createState() => _TrainingReaderState();
}

class _TrainingReaderState extends State<TrainingReader> {
  VideoPlayerController? player;
  String? error;
  bool ready = false;
  double? progress;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<File> target() async {
    final d = await getApplicationSupportDirectory();
    return File(
      '${d.path}/${widget.vm.user.id}-${widget.article['mediaId']}.mp4',
    );
  }

  Future<void> initialize() async {
    if (widget.article['type'] != 'video') return;
    try {
      final file = await target();
      player = await file.exists()
          ? VideoPlayerController.file(file)
          : VideoPlayerController.networkUrl(
              Uri.parse(
                '${widget.vm.api.http.options.baseUrl}/v1/media/${widget.article['mediaId']}',
              ),
              httpHeaders: {
                for (final e in widget.vm.api.http.options.headers.entries)
                  e.key: '${e.value}',
              },
            );
      await player!.initialize();
      if (mounted) setState(() => ready = true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = 'La vidéo est indisponible. Téléchargez-la lorsque la connexion sera rétablie.',
        );
      }
    }
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Formation')),
    body: Content(
      maxWidth: 840,
      children: [
        SectionTitle(widget.article['title']),
        if (error != null) Notice(error!, error: true),
        if (widget.article['type'] == 'video') ...[
          if (ready) ...[
            AspectRatio(
              aspectRatio: player!.value.aspectRatio,
              child: VideoPlayer(player!),
            ),
            ValueListenableBuilder(
              valueListenable: player!,
              builder: (context, value, _) => Column(
                children: [
                  VideoProgressIndicator(
                    player!,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  IconButton.filled(
                    onPressed: () =>
                        value.isPlaying ? player!.pause() : player!.play(),
                    icon: Icon(
                      value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    tooltip: value.isPlaying ? 'Pause' : 'Lire',
                  ),
                ],
              ),
            ),
          ] else if (error == null)
            const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: download,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Télécharger pour consulter hors ligne'),
          ),
          if (progress != null) LinearProgressIndicator(value: progress),
        ],
        const SizedBox(height: 20),
        SelectableText(
          widget.article['body']
              .toString()
              .replaceAll(RegExp(r'</(p|h2|h3|li)>'), '\n\n')
              .replaceAll(RegExp('<[^>]*>'), ''),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    ),
  );
  Future<void> download() async {
    try {
      final file = await target();
      final temp = File('${file.path}.part');
      await widget.vm.api.http.download(
        '/v1/media/${widget.article['mediaId']}',
        temp.path,
        onReceiveProgress: (n, total) {
          if (mounted && total > 0) setState(() => progress = n / total);
        },
      );
      await temp.rename(file.path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vidéo disponible hors ligne sur ce téléphone.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    }
  }
}
