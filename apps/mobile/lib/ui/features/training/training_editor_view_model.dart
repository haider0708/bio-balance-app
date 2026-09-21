import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../data/repositories/media_upload_repository.dart';
import '../../../data/repositories/training_repository.dart';
import '../../../domain/models/models.dart';
import '../../core/form_draft.dart';
import '../authentication/session_view_model.dart';
import '../workspace/workspace_view_model.dart';

@immutable
class TrainingEditorState {
  final Map<String, String> fields;
  final bool loading, busy, conflict;
  final double? progress;
  final String? error;
  const TrainingEditorState(
    this.fields, {
    this.loading = false,
    this.busy = false,
    this.conflict = false,
    this.progress,
    this.error,
  });
  String value(String key) => fields[key] ?? '';
}

class TrainingEditorViewModel extends ChangeNotifier {
  final WorkspaceViewModel workspace;
  late final FormDraftController draft;
  late final TrainingRepository repository = TrainingRepository(
    workspace.repository,
    workspace.api,
  );
  late final MediaUploadRepository uploads = MediaUploadRepository(
    workspace.repository,
    workspace.api,
  );
  final cancel = CancelToken();
  bool closed = false;
  TrainingEditorState state = const TrainingEditorState({}, loading: true);
  TrainingEditorViewModel(this.workspace, Json? article) {
    final values = <String, String>{
      'id': article?['id'] ?? const Uuid().v4(),
      'version': '${article?['version'] ?? 0}',
      'title': article?['title'] ?? '',
      'body': article?['body'] ?? '',
      'type': article?['type'] ?? 'article',
      'status': article?['status'] ?? 'draft',
      'mediaId': article?['mediaId'] ?? '',
      'productIds': jsonEncode(article?['productIds'] ?? []),
      'filePath': '',
      'fileName': '',
      'mediaStatus': article?['status'] == 'published' ? 'ready' : '',
    };
    state = TrainingEditorState(values, loading: true);
    draft = FormDraftController(
      workspace,
      null,
      'training:${article?['id'] ?? 'new'}',
      values,
    );
  }
  void emit({
    Map<String, String>? fields,
    bool? loading,
    bool? busy,
    bool? conflict,
    double? progress,
    String? error,
  }) {
    if (closed) return;
    state = TrainingEditorState(
      Map.unmodifiable(fields ?? state.fields),
      loading: loading ?? state.loading,
      busy: busy ?? state.busy,
      conflict: conflict ?? state.conflict,
      progress: progress ?? state.progress,
      error: error,
    );
    notifyListeners();
  }

  Future<void> restore() async {
    try {
      final saved = await draft.restore();
      if (closed) return;
      emit(fields: {...state.fields, ...?saved}, loading: false);
      await draft.change(state.fields);
    } catch (e) {
      emit(loading: false, error: SessionViewModel.message(e));
    }
  }

  void change(Map<String, String> values) {
    emit(fields: {...state.fields, ...values});
    unawaited(
      draft
          .change(state.fields)
          .catchError((Object e) => emit(error: SessionViewModel.message(e))),
    );
  }

  List<String> get productIds =>
      List<String>.from(jsonDecode(state.value('productIds')));
  Future<void> upload(String path, String name) async {
    if (state.busy) return;
    change({'filePath': path, 'fileName': name});
    emit(busy: true, progress: 0);
    try {
      final asset = await uploads.upload(
        accountId: workspace.user.id,
        file: File(path),
        name: name,
        mime: name.toLowerCase().endsWith('.mov')
            ? 'video/quicktime'
            : 'video/mp4',
        purpose: 'training',
        cancel: cancel,
        progress: (value) => emit(progress: value),
      );
      if (closed) return;
      change({'mediaId': asset['id'], 'mediaStatus': asset['status']});
    } catch (e) {
      emit(error: SessionViewModel.message(e));
    } finally {
      emit(busy: false, error: state.error);
    }
  }

  Future<void> checkMedia() async {
    if (state.value('mediaId').isEmpty) return;
    try {
      final value = await uploads.status(state.value('mediaId'));
      if (!closed) change({'mediaStatus': value['status']});
    } catch (e) {
      emit(error: SessionViewModel.message(e));
    }
  }

  Future<bool> save() async {
    emit(busy: true);
    try {
      final fields = state.fields;
      if (fields['title']!.trim().length < 3) {
        throw const FormatException(
          'Le titre doit contenir au moins trois caractères.',
        );
      }
      if (fields['type'] == 'video' && fields['mediaId']!.isEmpty) {
        throw const FormatException('Ajoutez une vidéo avant de sauvegarder.');
      }
      if (fields['status'] == 'published' && fields['type'] == 'video') {
        await checkMedia();
        if (state.value('mediaStatus') != 'ready') {
          throw const AppFailure(
            'MEDIA_PROCESSING',
            'Attendez la fin du traitement avant de publier.',
          );
        }
      }
      await draft.change(state.fields);
      final accepted = await repository.save(workspace.user.id, {
        'id': fields['id'],
        'expectedVersion': int.parse(fields['version']!),
        'title': fields['title'],
        'body': fields['body'],
        'type': fields['type'],
        'status': fields['status'],
        'mediaId': fields['type'] == 'video' ? fields['mediaId'] : null,
        'productIds': productIds,
      });
      emit(
        fields: {...state.fields, 'version': '${accepted['version']}'},
        conflict: false,
      );
      await draft.change(state.fields);
      await draft.complete();
      return true;
    } catch (e) {
      emit(
        error: SessionViewModel.message(e),
        conflict:
            e is DioException &&
            e.response?.data is Map &&
            e.response?.data['code'] == 'VERSION_CONFLICT',
      );
      return false;
    } finally {
      emit(busy: false, error: state.error);
    }
  }

  Future<Json?> currentVersion() async {
    emit(busy: true);
    try {
      return await repository.get(state.value('id'));
    } catch (e) {
      emit(error: SessionViewModel.message(e));
      return null;
    } finally {
      emit(busy: false, error: state.error);
    }
  }

  void confirmVersion(Json current) {
    if (current['id'] != state.value('id')) return;
    change({'version': '${current['version']}'});
    emit(conflict: false);
  }

  Json preview() => {
    'id': state.value('id'),
    'title': state.value('title'),
    'body': state.value('body'),
    'type': state.value('type'),
    'mediaId': state.value('mediaId').isEmpty ? null : state.value('mediaId'),
    'productIds': productIds,
    'status': state.value('status'),
  };
  @override
  void dispose() {
    closed = true;
    cancel.cancel();
    draft.dispose();
    super.dispose();
  }
}
