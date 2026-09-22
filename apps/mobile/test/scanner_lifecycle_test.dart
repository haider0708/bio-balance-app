import 'dart:async';

import 'package:biobalance/ui/features/scanning/scanner_view_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ControlledCamera extends MobileScannerPlatform {
  final options = <StartOptions>[];
  final events = StreamController<BarcodeCapture?>.broadcast();
  Completer<void>? starting, stopping;
  int active = 0, stops = 0, maximumActive = 0;
  @override
  Stream<BarcodeCapture?> get barcodesStream => events.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Future<MobileScannerViewAttributes> start(StartOptions value) async {
    options.add(value);
    await starting?.future;
    active++;
    if (active > maximumActive) maximumActive = active;
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    await stopping?.future;
    active--;
  }

  @override
  Future<void> dispose() async {}
  @override
  Future<void> toggleTorch() async {}
  @override
  Widget buildCameraView() => const SizedBox();
}

Future<void> preview(WidgetTester t, ScannerViewModel vm) => t.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: SizedBox(
      width: 320,
      height: 300,
      child: MobileScanner(key: ObjectKey(vm), controller: vm.controller),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MobileScannerPlatform original;
  late ControlledCamera camera;
  late ScannerViewModel vm;
  setUp(() {
    original = MobileScannerPlatform.instance;
    camera = ControlledCamera();
    MobileScannerPlatform.instance = camera;
  });
  tearDown(() async {
    await camera.events.close();
    MobileScannerPlatform.instance = original;
    MobileScannerController.resetPlatformSessionOwner();
  });

  testWidgets(
    'decoding is throttled, without frame copies or format restrictions',
    (t) async {
      vm = ScannerViewModel();
      await preview(t, vm);
      vm.setActive(true);
      await t.pump();
      await t.pump();
      final options = camera.options.single;
      expect(options.detectionSpeed, DetectionSpeed.normal);
      expect(options.detectionTimeoutMs, 250);
      expect(options.cameraResolution, const Size(640, 480));
      expect(options.returnImage, isFalse);
      expect(options.formats, isEmpty);
      await t.pumpWidget(const SizedBox());
      vm.dispose();
      await t.pump();
      await t.pump();
      expect(camera.active, 0);
    },
  );

  testWidgets('late permission grant after closing releases the camera', (
    t,
  ) async {
    vm = ScannerViewModel();
    await preview(t, vm);
    camera.starting = Completer();
    vm.setActive(true);
    await t.pump();
    expect(camera.options.length, 1);
    await t.pumpWidget(const SizedBox());
    vm.dispose();
    camera.starting!.complete();
    await t.pump();
    await t.pump();
    expect(camera.active, 0);
    expect(camera.stops, 1);
  });

  testWidgets(
    'background during startup releases camera; resume waits for stop',
    (t) async {
      vm = ScannerViewModel();
      await preview(t, vm);
      camera.starting = Completer();
      vm.setActive(true);
      await t.pump();
      vm.setActive(false);
      camera.starting!.complete();
      await t.pump();
      await t.pump();
      expect(camera.active, 0);
      vm.setActive(true);
      await t.pump();
      await t.pump();
      camera.stopping = Completer();
      vm.setActive(false);
      await t.pump();
      vm.setActive(true);
      vm.toggleTorch();
      expect(camera.options.length, 2);
      camera.stopping!.complete();
      await t.pump();
      await t.pump();
      expect(camera.options.length, 3);
      expect(camera.maximumActive, 1);
      await t.pumpWidget(const SizedBox());
      vm.dispose();
      await t.pump();
      await t.pump();
      expect(camera.active, 0);
    },
  );

  testWidgets(
    'empty detections ignored; a burst of identical frames captures once',
    (t) async {
      vm = ScannerViewModel();
      await preview(t, vm);
      vm.setActive(true);
      await t.pump();
      await t.pump();
      expect(vm.accept([null, '  ']), isNull);
      expect(vm.accept([null, '0012345678905']), '0012345678905');
      for (var i = 0; i < 50; i++) {
        expect(vm.accept(['0012345678905']), isNull);
      }
      await t.pump();
      await t.pump();
      expect(camera.active, 0);
      vm.setActive(false);
      vm.setActive(true);
      await t.pump();
      await t.pump();
      expect(camera.options.length, 1);
      await t.pumpWidget(const SizedBox());
      vm.dispose();
      await t.pump();
      await t.pump();
    },
  );

  testWidgets('decoder errors stop scanning and an explicit retry recovers', (
    t,
  ) async {
    vm = ScannerViewModel();
    await preview(t, vm);
    vm.setActive(true);
    await t.pump();
    vm.detectionFailed();
    await t.pump();
    expect(vm.error, isNotNull);
    expect(camera.active, 0);
    expect(vm.accept(['619123']), isNull);
    vm.retry();
    await t.pump();
    expect(vm.error, isNull);
    expect(camera.active, 1);
    await t.pumpWidget(const SizedBox());
    vm.dispose();
    await t.pump();
  });

  testWidgets(
    'repeated open capture close cycles leave no active native session',
    (t) async {
      for (var i = 0; i < 30; i++) {
        vm = ScannerViewModel();
        await preview(t, vm);
        vm.setActive(true);
        await t.pump();
        await t.pump();
        expect(vm.accept(['6190000000010']), '6190000000010');
        await t.pumpWidget(const SizedBox());
        vm.dispose();
        await t.pump();
        await t.pump();
        expect(camera.active, 0);
      }
      expect(camera.options.length, 30);
      expect(camera.maximumActive, 1);
    },
  );
}
