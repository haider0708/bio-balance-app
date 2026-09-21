import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../domain/models/models.dart';
import '../services/api/generated/api_client.dart';
import 'offline_repository.dart';

class MediaUploadRepository {
  final OfflineRepository local;
  final ApiClient api;
  MediaUploadRepository(this.local, this.api);
  Future<Json> status(String id) async => Map<String, dynamic>.from(
    await api.request('GET', '/v1/media/uploads/$id'),
  );

  Future<Json> upload({
    required String accountId,
    required File file,
    required String name,
    required String mime,
    required String purpose,
    Store? store,
    required CancelToken cancel,
    required void Function(double) progress,
  }) async {
    final binding = api.binding;
    if (binding.accountId != accountId) {
      throw const AppFailure('ACCOUNT_CHANGED', 'Reconnectez-vous.');
    }
    final size = await file.length();
    final image = mime.startsWith('image/');
    if (size <= 0 || size > (image ? 10 : 500) * 1024 * 1024) {
      throw FormatException(
        image
            ? 'Choisissez une image JPEG ou PNG de 10 Mo maximum.'
            : 'La vidéo ne doit pas dépasser 500 Mo.',
      );
    }
    var contentMime = mime;
    if (image) {
      final handle = await file.open();
      try {
        final prefix = await handle.read(8);
        final png =
            prefix.length == 8 &&
            prefix.asMap().entries.every(
              (e) => e.value == [137, 80, 78, 71, 13, 10, 26, 10][e.key],
            );
        final jpeg = prefix.length >= 2 && prefix[0] == 255 && prefix[1] == 216;
        if (!png && !jpeg) {
          throw const FormatException(
            'Choisissez une image JPEG ou PNG valide.',
          );
        }
        contentMime = png ? 'image/png' : 'image/jpeg';
      } finally {
        await handle.close();
      }
    }
    final checksum = (await sha256.bind(file.openRead()).first).toString();
    api.requireBinding(binding);
    if (cancel.isCancelled) throw cancel.cancelError!;
    final key = 'upload:$purpose:$name:$size:$checksum';
    final cached = await local.draft(accountId, store?.id ?? '', key);
    Json asset;
    if (cached != null && cached['id'] != null) {
      asset = await status(cached['id']);
      if (integer(asset['size']) != size ||
          asset['expectedSha256'] != checksum) {
        throw const AppFailure(
          'UPLOAD_IDENTITY',
          'Le fichier ne correspond plus au téléversement.',
        );
      }
    } else {
      asset = Map<String, dynamic>.from(
        await api.request(
          'POST',
          '/v1/media/uploads',
          body: {
            'fileName': name,
            'mime': contentMime,
            'size': size,
            'sha256': checksum,
            'purpose': purpose,
            if (store != null) 'organizationId': store.organizationId,
            if (store != null) 'storeId': store.id,
          },
        ),
      );
      api.requireBinding(binding);
      await local.saveDraft(accountId, store?.id ?? '', key, {
        'id': asset['id'],
        'size': size,
        'sha256': checksum,
      });
    }
    var offset = integer(asset['received']);
    if (asset['status'] == 'failed') {
      throw const AppFailure(
        'MEDIA_FAILED',
        'Ce fichier n’a pas pu être traité. Choisissez un autre fichier.',
      );
    }
    final handle = await file.open();
    try {
      while (offset < size) {
        api.requireBinding(binding);
        if (cancel.isCancelled) throw cancel.cancelError!;
        await handle.setPosition(offset);
        final bytes = await handle.read(4 * 1024 * 1024);
        if (bytes.isEmpty) {
          throw const AppFailure(
            'FILE_CHANGED',
            'Le fichier a changé pendant le transfert.',
          );
        }
        final response = await api.http.put(
          '/v1/media/uploads/${asset['id']}',
          data: Stream.value(bytes),
          cancelToken: cancel,
          options: Options(
            headers: {
              'Authorization': binding.authorization,
              'Content-Type': 'application/octet-stream',
              'Upload-Offset': '$offset',
              'Content-Length': '${bytes.length}',
            },
          ),
        );
        api.requireBinding(binding);
        final next = integer(response.data['received']);
        if (next <= offset || next > size) {
          throw const AppFailure(
            'UPLOAD_OFFSET',
            'Position de téléversement invalide.',
          );
        }
        offset = next;
        progress(offset / size);
      }
    } finally {
      await handle.close();
    }
    api.requireBinding(binding);
    progress(1);
    return status(asset['id']);
  }
}
