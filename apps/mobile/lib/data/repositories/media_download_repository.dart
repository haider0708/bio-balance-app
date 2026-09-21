import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models/models.dart';
import '../services/api/generated/api_client.dart';
import 'offline_repository.dart';
import 'media_upload_repository.dart';

class MediaDownloadRepository {
  final ApiClient api;
  final OfflineRepository local;
  final Future<Directory> Function() directory;
  MediaDownloadRepository(
    this.local,
    this.api, {
    Future<Directory> Function()? directory,
  }) : directory = directory ?? getApplicationSupportDirectory;
  Future<File> target(String account, String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(account) ||
        !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id)) {
      throw const AppFailure('INVALID_MEDIA', 'Identifiant du média invalide.');
    }
    final root = await directory();
    return File('${root.path}/$account-$id.mp4');
  }

  Future<File?> cached(String account, String id) async {
    final record = await local.draft(account, '', 'download:$id');
    if (record?['status'] != 'ready') return null;
    final file = await target(account, id);
    return await file.exists() &&
            await file.length() == integer(record?['size'])
        ? file
        : null;
  }

  Future<File> download(
    String account,
    String id,
    CancelToken cancel,
    void Function(double) progress,
  ) async {
    final binding = api.binding;
    if (binding.accountId != account) {
      throw const AppFailure('ACCOUNT_CHANGED', 'Reconnectez-vous.');
    }
    final metadata = (await api.trainingMetadata(id: id)).toJson();
    final size = integer(metadata['size']), checksum = '${metadata['sha256']}';
    if (metadata['id'] != id ||
        size <= 0 ||
        size > 2 * 1024 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
      throw const AppFailure(
        'INVALID_MEDIA',
        'Les informations du fichier sont invalides.',
      );
    }
    final file = await target(account, id),
        partial = File('${(await target(account, id)).path}.part');
    final old = await local.draft(account, '', 'download:$id');
    api.requireBinding(binding);
    if (cancel.isCancelled) throw cancel.cancelError!;
    if (await file.exists() &&
        await file.length() == size &&
        await fileChecksum(file.path) == checksum) {
      api.requireBinding(binding);
      await local.saveDraft(account, '', 'download:$id', {
        'status': 'ready',
        'size': size,
        'sha256': checksum,
      });
      return file;
    }
    if (await partial.exists() &&
        (old?['sha256'] != checksum ||
            integer(old?['size']) != size ||
            await partial.length() > size)) {
      await partial.delete();
    }
    await file.parent.create(recursive: true);
    await local.db.transaction(() async {
      api.requireBinding(binding);
      await local.saveDraft(account, '', 'download:$id', {
        'status': 'partial',
        'size': size,
        'sha256': checksum,
      });
    });
    var offset = await partial.exists() ? await partial.length() : 0;
    progress(offset / size);
    if (offset < size) {
      api.requireBinding(binding);
      final response = await api.transfer<ResponseBody>(
        'GET',
        '/v1/media/$id',
        responseType: ResponseType.stream,
        cancelToken: cancel,
        headers: {
          'Accept-Encoding': 'identity',
          if (offset > 0) 'Range': 'bytes=$offset-',
          if (offset > 0) 'If-Range': '"$checksum"',
        },
        validateStatus: (code) => code == 200 || code == 206,
      );
      api.requireBinding(binding);
      if (response.statusCode == 200) offset = 0;
      if (response.statusCode == 206) {
        final range = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
            .firstMatch(response.headers.value('content-range') ?? '');
        if (range == null ||
            int.parse(range[1]!) != offset ||
            int.parse(range[2]!) != size - 1 ||
            int.parse(range[3]!) != size) {
          await response.data!.stream.listen((_) {}).cancel();
          throw const AppFailure(
            'DOWNLOAD_RANGE',
            'La reprise du fichier a été refusée. Réessayez.',
          );
        }
      }
      final declared = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
      if (declared != null && declared != size - offset) {
        await response.data!.stream.listen((_) {}).cancel();
        throw const AppFailure(
          'DOWNLOAD_LENGTH',
          'La taille annoncée est incohérente.',
        );
      }
      RandomAccessFile? handle;
      var unflushed = 0;
      try {
        handle = await partial.open(
          mode: offset == 0 ? FileMode.write : FileMode.append,
        );
        await for (final bytes in response.data!.stream) {
          api.requireBinding(binding);
          if (cancel.isCancelled) throw cancel.cancelError!;
          if (offset + bytes.length > size) {
            throw const AppFailure(
              'DOWNLOAD_LENGTH',
              'Le fichier dépasse la taille attendue.',
            );
          }
          await handle.writeFrom(bytes);
          offset += bytes.length;
          unflushed += bytes.length;
          if (unflushed >= 4 * 1024 * 1024) {
            await handle.flush();
            unflushed = 0;
          }
          progress(offset / size);
        }
        await handle.flush();
      } finally {
        if (handle != null) {
          await handle.close();
        } else {
          await response.data!.stream.listen((_) {}).cancel();
        }
      }
      if (offset != size) {
        throw const AppFailure(
          'DOWNLOAD_INTERRUPTED',
          'Téléchargement interrompu. Vous pouvez reprendre.',
        );
      }
    }
    if (await fileChecksum(partial.path) != checksum) {
      await partial.delete();
      throw const AppFailure(
        'DOWNLOAD_CHECKSUM',
        'Le fichier reçu est altéré. Recommencez le téléchargement.',
      );
    }
    api.requireBinding(binding);
    if (cancel.isCancelled) throw cancel.cancelError!;
    await partial.rename(file.path);
    await local.db.transaction(() async {
      api.requireBinding(binding);
      await local.saveDraft(account, '', 'download:$id', {
        'status': 'ready',
        'size': size,
        'sha256': checksum,
      });
    });
    progress(1);
    return file;
  }
}
