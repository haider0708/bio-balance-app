import 'dart:io';
import 'dart:typed_data';

import 'package:biobalance/core/files/media_cache_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Folder extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Folder(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('media-cache');
    PathProviderPlatform.instance = _Folder(root.path);
  });
  tearDown(() async {
    await MediaCache.clear();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  const id = '0b7d2a4e-1c3f-4d5e-8a9b-112233445566';

  test('keeps a downloaded file and gives it back', () async {
    expect(await MediaCache.read(id), isNull);
    await MediaCache.write(id, Uint8List.fromList([1, 2, 3]));
    expect(await MediaCache.read(id), [1, 2, 3]);
  });

  test('never turns an id it did not make into a path', () async {
    await MediaCache.write('../escape', Uint8List.fromList([9]));
    expect(await MediaCache.read('../escape'), isNull);
    expect(File('${root.path}/escape').existsSync(), isFalse);
  });

  test('leaves nothing behind after signing out', () async {
    await MediaCache.write(id, Uint8List.fromList([1]));
    await MediaCache.clear();
    expect(await MediaCache.read(id), isNull);
  });
}
