import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models/models.dart';
import '../services/api/generated/models.dart';
import 'repository_context.dart';

class ExportRepository {
  final RepositoryContext context;
  ExportRepository(this.context);
  Future<Json> create(String id, Json query) => context.run(
    () async => (await context.api.exportCreate(
      body: ExportCreateRequestDto.fromJson({'id': id, 'query': query}),
    )).toJson(),
  );
  Future<Json> status(String id) =>
      context.run(() async => (await context.api.exportGet(id: id)).toJson());
  Future<File> download(String id, CancelToken cancel) => context.run(() async {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw const FormatException('Export invalide.');
    }
    final root = await getTemporaryDirectory(),
        file = File(
          '${root.path}/biobalance-${context.binding.accountId}-$id.csv',
        );
    await for (final entry in root.list()) {
      if (entry is File &&
          entry.path.split('/').last.startsWith('biobalance-') &&
          entry.path.endsWith('.csv') &&
          DateTime.now().difference((await entry.stat()).modified).inHours >=
              24) {
        await entry.delete().catchError((Object _) => entry);
      }
    }
    final response = await context.api.transfer<ResponseBody>(
      'GET',
      '/v1/report-exports/$id/file',
      cancelToken: cancel,
      responseType: ResponseType.stream,
      headers: {'Accept-Encoding': 'identity'},
    );
    final expected = int.tryParse(
      response.headers.value('content-length') ?? '',
    );
    if (expected == null || expected < 1 || expected > 256 * 1024 * 1024) {
      await response.data!.stream.listen((_) {}).cancel();
      throw const FormatException('Taille d’export invalide.');
    }
    RandomAccessFile? handle;
    var received = 0;
    var listening = false;
    try {
      handle = await file.open(mode: FileMode.write);
      listening = true;
      await for (final bytes in response.data!.stream) {
        context.check();
        if (cancel.isCancelled) throw cancel.cancelError!;
        received += bytes.length;
        if (received > expected) {
          throw const FormatException('Export incomplet.');
        }
        await handle.writeFrom(bytes);
      }
      if (received != expected) {
        throw const FormatException(
          'Export incomplet. Réessayez le téléchargement.',
        );
      }
      await handle.flush();
      context.check();
    } catch (_) {
      await handle?.close();
      handle = null;
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      if (handle != null) await handle.close();
      if (!listening) await response.data!.stream.listen((_) {}).cancel();
    }
    return file;
  });
}
