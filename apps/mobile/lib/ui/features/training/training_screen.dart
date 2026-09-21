import 'dart:async';

import '../../../data/repositories/training_repository.dart';
import '../../../data/repositories/media_download_repository.dart';
import '../../../domain/models/training_text.dart';
import 'training_editor_view_model.dart';

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
  String? productFilter;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final vm = widget.vm;
    final repository = TrainingRepository(vm.repository, vm.api);
    try {
      final cached = await repository.cached(vm.user.id);
      if (mounted) setState(() => articles = cached);
      final items = await repository.refresh(vm.user.id);
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
              (widget.vm.user.admin || a['status'] == 'published') &&
              '${a['title']} ${TrainingText.plain(a['body'] ?? '')}'
                  .toLowerCase()
                  .contains(query.toLowerCase()) &&
              (productFilter == null ||
                  (a['productIds'] as List? ?? []).contains(productFilter)),
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
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: productFilter ?? '',
          isExpanded: true,
          items: [
            const DropdownMenuItem(value: '', child: Text('Tous les produits')),
            ...?widget.vm.state.data?.products.map(
              (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
            ),
          ],
          onChanged: (id) =>
              setState(() => productFilter = id == '' ? null : id),
          decoration: const InputDecoration(labelText: 'Produit associé'),
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
                        '${article['type'] == 'video' ? 'Vidéo' : 'Article'}${widget.vm.user.admin ? ' · ${publicationLabel(article['status'])}' : ''}',
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
  late final editor = TrainingEditorViewModel(widget.vm, widget.article);
  final title = TextEditingController(), body = TextEditingController();
  bool initialized = false;
  @override
  void initState() {
    super.initState();
    unawaited(restore());
  }

  Future<void> restore() async {
    await editor.restore();
    if (!mounted) return;
    title.text = editor.state.value('title');
    body.text = editor.state.value('body');
    title.addListener(() => editor.change({'title': title.text}));
    body.addListener(() => editor.change({'body': body.text}));
    setState(() => initialized = true);
  }

  @override
  void dispose() {
    editor.dispose();
    title.dispose();
    body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: editor,
    builder: (context, _) {
      final state = editor.state;
      final blocked = state.busy || !initialized;
      return Scaffold(
        appBar: AppBar(title: const Text('Éditer une formation')),
        body: Content(
          maxWidth: 760,
          children: [
            if (state.error != null) Notice(state.error!, error: true),
            if (state.conflict)
              OutlinedButton(
                onPressed: blocked ? null : compareVersion,
                child: const Text('Comparer avec la version actuelle'),
              ),
            if (!initialized) const LinearProgressIndicator(),
            TextField(
              controller: title,
              enabled: initialized && !state.busy,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Titre'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: body,
              enabled: initialized && !state.busy,
              minLines: 6,
              maxLines: 15,
              decoration: const InputDecoration(
                labelText: 'Article ou description',
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              children: [
                for (final type in ['article', 'video'])
                  ChoiceChip(
                    label: Text(type == 'article' ? 'Article' : 'Vidéo'),
                    selected: state.value('type') == type,
                    onSelected: blocked
                        ? null
                        : (_) => editor.change({'type': type}),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: blocked ? null : associate,
              icon: const Icon(Icons.link),
              label: const Text('Associer des produits'),
            ),
            Wrap(
              spacing: 8,
              children: editor.productIds
                  .map((id) => Chip(label: Text(widget.vm.productName(id))))
                  .toList(),
            ),
            if (state.value('type') == 'video') ...[
              OutlinedButton.icon(
                onPressed: blocked ? null : upload,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choisir une vidéo'),
              ),
              if (state.value('filePath').isNotEmpty &&
                  state.value('mediaStatus') != 'ready')
                TextButton(
                  onPressed: blocked
                      ? null
                      : () => editor.upload(
                          state.value('filePath'),
                          state.value('fileName'),
                        ),
                  child: const Text('Reprendre le transfert'),
                ),
              if (state.progress != null) ...[
                LinearProgressIndicator(value: state.progress),
                Text('${(state.progress! * 100).round()} % téléversé'),
              ],
              if (state.value('mediaId').isNotEmpty) ...[
                Text(mediaStatusLabel(state.value('mediaStatus'))),
                TextButton(
                  onPressed: blocked ? null : editor.checkMedia,
                  child: const Text('Vérifier le traitement'),
                ),
                TextButton(
                  onPressed: blocked
                      ? null
                      : () => editor.change({
                          'mediaId': '',
                          'mediaStatus': '',
                          'filePath': '',
                          'fileName': '',
                        }),
                  child: const Text('Retirer la vidéo'),
                ),
              ],
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: ValueKey(state.value('status')),
              initialValue: state.value('status'),
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'draft', child: Text('Brouillon')),
                DropdownMenuItem(value: 'published', child: Text('Publié')),
                DropdownMenuItem(value: 'archived', child: Text('Archivé')),
              ],
              onChanged: blocked
                  ? null
                  : (value) => editor.change({'status': value!}),
              decoration: const InputDecoration(labelText: 'Visibilité'),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: !initialized
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TrainingReader(
                          vm: widget.vm,
                          article: editor.preview(),
                          preview: true,
                          mediaReady: state.value('mediaStatus') == 'ready',
                        ),
                      ),
                    ),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Aperçu du contenu'),
            ),
            FilledButton(
              onPressed: blocked || state.conflict
                  ? null
                  : () async {
                      if (await editor.save() && context.mounted) {
                        Navigator.pop(context);
                      }
                    },
              child: const Text('Enregistrer le contenu'),
            ),
          ],
        ),
      );
    },
  );
  Future<void> compareVersion() async {
    final current = await editor.currentVersion();
    if (!mounted || current == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Version actuelle sur le serveur'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${current['title']}'),
              Text(TrainingText.plain(current['body'] ?? '')),
              const SizedBox(height: 16),
              const Text(
                'Votre brouillon est conservé. Confirmez pour appliquer vos modifications à cette version lors du prochain enregistrement.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuer à comparer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Conserver mes modifications'),
          ),
        ],
      ),
    );
    if (mounted && confirmed == true) editor.confirmVersion(current);
  }

  Future<void> upload() async {
    final selected = await FilePicker.pickFiles(type: FileType.video);
    if (!mounted || selected.isEmpty || selected.single.path == null) return;
    await editor.upload(selected.single.path!, selected.single.name);
  }

  Future<void> associate() async {
    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ProductAssociationSheet(
        products: widget.vm.state.data?.products ?? [],
        selected: editor.productIds,
      ),
    );
    if (chosen != null && mounted) {
      editor.change({'productIds': jsonEncode(chosen)});
    }
  }
}

String mediaStatusLabel(String status) => switch (status) {
  'uploading' => 'Transfert en cours',
  'processing' => 'Vidéo reçue · Traitement en cours',
  'ready' => 'Vidéo prête à publier',
  'failed' => 'Traitement échoué · Choisissez un autre fichier',
  _ => 'État du média à vérifier',
};
String publicationLabel(String status) => switch (status) {
  'published' => 'Publié',
  'archived' => 'Archivé',
  _ => 'Brouillon',
};

class ProductAssociationSheet extends StatefulWidget {
  final List<Product> products;
  final List<String> selected;
  const ProductAssociationSheet({
    super.key,
    required this.products,
    required this.selected,
  });
  @override
  State<ProductAssociationSheet> createState() =>
      _ProductAssociationSheetState();
}

class _ProductAssociationSheetState extends State<ProductAssociationSheet> {
  late final selected = widget.selected.toSet();
  String query = '';
  @override
  Widget build(BuildContext context) {
    final products = widget.products
        .where(
          (p) => '${p.name} ${p.reference}'.toLowerCase().contains(
            query.toLowerCase(),
          ),
        )
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ListView.builder(
          itemCount: products.length + 3,
          itemBuilder: (context, index) {
            if (index == 0) return const SectionTitle('Produits associés');
            if (index == 1) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TextField(
                  onChanged: (value) => setState(() => query = value),
                  decoration: const InputDecoration(
                    labelText: 'Rechercher un produit',
                  ),
                ),
              );
            }
            if (index == products.length + 2) {
              return FilledButton(
                onPressed: () => Navigator.pop(context, selected.toList()),
                child: Text('Associer ${selected.length} produit(s)'),
              );
            }
            final product = products[index - 2];
            return CheckboxListTile(
              value: selected.contains(product.id),
              title: Text(product.name),
              subtitle: Text(product.reference),
              onChanged: (value) => setState(
                () => value == true
                    ? selected.add(product.id)
                    : selected.remove(product.id),
              ),
            );
          },
        ),
      ),
    );
  }
}

class TrainingReader extends StatefulWidget {
  final WorkspaceViewModel vm;
  final Json article;
  final bool preview, mediaReady;
  const TrainingReader({
    super.key,
    required this.vm,
    required this.article,
    this.preview = false,
    this.mediaReady = true,
  });
  @override
  State<TrainingReader> createState() => _TrainingReaderState();
}

class _TrainingReaderState extends State<TrainingReader>
    with WidgetsBindingObserver {
  late final downloads = MediaDownloadRepository(
    widget.vm.repository,
    widget.vm.api,
  );
  final transfers = CancelToken();
  VideoPlayerController? player;
  String? error;
  bool ready = false, downloading = false, offlineReady = false;
  double? progress;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(player?.pause());
  }

  Future<void> initialize() async {
    if (widget.article['type'] != 'video' ||
        !widget.mediaReady ||
        widget.article['mediaId'] == null) {
      return;
    }
    final run = ++generation, binding = widget.vm.api.binding;
    final previous = player;
    player = null;
    await previous?.dispose();
    if (!mounted || run != generation) return;
    setState(() {
      ready = false;
      error = null;
    });
    try {
      final cached = await downloads.cached(
        widget.vm.user.id,
        widget.article['mediaId'],
      );
      if (!mounted || run != generation) return;
      widget.vm.api.requireBinding(binding);
      final controller = cached != null
          ? VideoPlayerController.file(cached)
          : VideoPlayerController.networkUrl(
              Uri.parse(widget.vm.api.http.options.baseUrl)
                  .resolve('/v1/media/${widget.article['mediaId']}'),
              httpHeaders: {
                if (binding.authorization != null)
                  'Authorization': binding.authorization!,
              },
            );
      player = controller;
      await controller.initialize();
      if (!mounted || run != generation) return;
      widget.vm.api.requireBinding(binding);
      setState(() {
        ready = true;
        offlineReady = cached != null;
      });
    } catch (e) {
      if (mounted && run == generation) {
        setState(
          () => error = 'La vidéo est indisponible. Reprenez le téléchargement lorsque la connexion sera rétablie.',
        );
      }
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    transfers.cancel();
    unawaited(player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.preview ? 'Aperçu de la formation' : 'Formation'),
    ),
    body: Content(
      maxWidth: 840,
      children: [
        SectionTitle(widget.article['title']),
        Wrap(
          spacing: 8,
          children: List<String>.from(widget.article['productIds'] ?? [])
              .map((id) => Chip(label: Text(widget.vm.productName(id))))
              .toList(),
        ),
        if (error != null) Notice(error!, error: true),
        if (widget.article['type'] == 'video') ...[
          if (!widget.mediaReady || widget.article['mediaId'] == null)
            const Notice(
              'La vidéo sera disponible après la fin de son transfert et de son traitement.',
            )
          else if (ready) ...[
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
          if (!widget.preview) ...[
            OutlinedButton.icon(
              onPressed: downloading || offlineReady ? null : download,
              icon: Icon(
                offlineReady ? Icons.download_done : Icons.download_outlined,
              ),
              label: Text(
                offlineReady
                    ? 'Vidéo disponible hors ligne'
                    : 'Télécharger ou reprendre hors ligne',
              ),
            ),
            if (progress != null) ...[
              LinearProgressIndicator(value: progress),
              Text('${(progress! * 100).round()} % téléchargé'),
            ],
          ],
        ],
        const SizedBox(height: 20),
        SelectableText(
          TrainingText.plain(widget.article['body'] ?? ''),
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    ),
  );
  Future<void> download() async {
    if (downloading) return;
    setState(() {
      downloading = true;
      error = null;
    });
    try {
      await downloads.download(
        widget.vm.user.id,
        widget.article['mediaId'],
        transfers,
        (value) {
          if (mounted) setState(() => progress = value);
        },
      );
      if (mounted) await initialize();
    } catch (e) {
      if (mounted) setState(() => error = SessionViewModel.message(e));
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }
}
