import 'dart:async';
import 'dart:io';

import 'package:biobalance/data/repositories/media_download_repository.dart';
import 'package:biobalance/data/services/api/generated/api_client.dart';
import 'package:biobalance/data/services/local_database/database.dart';
import 'package:biobalance/domain/models/models.dart';
import 'package:biobalance/ui/features/training/training_screen.dart';
import 'package:biobalance/ui/features/workspace/workspace_view_model.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart'
    as platform;

import 'session_test.dart' show MemoryDraftRepository;

class ReadyDownload extends MediaDownloadRepository {
  bool available = false;
  ReadyDownload(super.local, super.api);
  @override
  Future<File?> cached(String account, String id) async =>
      available ? File('/verified-offline-video.mp4') : null;
  @override
  Future<File> download(
    String account,
    String id,
    CancelToken cancel,
    void Function(double) progress,
  ) async {
    available = true;
    progress(1);
    return File('/verified-offline-video.mp4');
  }
}

class DelayedVideoDisposal extends platform.VideoPlayerPlatform {
  final disposing = Completer<void>(), release = Completer<void>();
  final disposed = <int>[];
  int nextId = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(platform.VideoCreationOptions options) async =>
      ++nextId;
  @override
  Stream<platform.VideoEvent> videoEventsFor(int playerId) => Stream.value(
    platform.VideoEvent(
      eventType: platform.VideoEventType.initialized,
      duration: const Duration(seconds: 5),
      size: const Size(320, 180),
    ),
  );
  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    if (playerId == 1) {
      disposing.complete();
      await release.future;
    }
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Widget buildViewWithOptions(platform.VideoViewOptions options) =>
      const SizedBox();
}

void main() {
  testWidgets(
    'switching to downloaded video stays safe while native disposal is pending',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final previousPlatform = platform.VideoPlayerPlatform.instance;
      final video = DelayedVideoDisposal();
      platform.VideoPlayerPlatform.instance = video;
      addTearDown(
        () => platform.VideoPlayerPlatform.instance = previousPlatform,
      );
      final db = AppDatabase(NativeDatabase.memory());
      final api = ApiClient(baseUrl: 'http://test')
        ..authenticate('token', accountId: 'seller');
      final local = MemoryDraftRepository(db, api);
      final vm = WorkspaceViewModel(
        const UserAccount(
          id: 'seller',
          name: 'Seller',
          email: 'seller@example.test',
          admin: false,
        ),
        local,
        api,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TrainingReader(
            vm: vm,
            downloads: ReadyDownload(local, api),
            article: const {
              'title': 'Formation',
              'type': 'video',
              'mediaId': 'video',
              'body': '',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller
            .dataSourceType,
        platform.DataSourceType.network,
      );
      await tester.ensureVisible(
        find.text('Télécharger ou reprendre hors ligne'),
      );
      await tester.tap(find.text('Télécharger ou reprendre hors ligne'));
      await tester.pump();
      // The plugin cancels its event stream before calling native disposal.
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(video.disposing.isCompleted, isTrue);
      expect(find.byType(VideoPlayer), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.takeException(), isNull);
      video.release.complete();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<VideoPlayer>(find.byType(VideoPlayer))
            .controller
            .dataSourceType,
        platform.DataSourceType.file,
      );
      expect(find.text('Vidéo disponible hors ligne'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
      expect(video.disposed, [1, 2]);
      expect(tester.takeException(), isNull);
      vm.dispose();
      await db.close();
    },
  );
}
