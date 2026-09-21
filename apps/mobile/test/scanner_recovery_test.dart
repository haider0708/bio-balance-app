import 'dart:async';

import 'package:biobalance/ui/core/design.dart';
import 'package:biobalance/ui/features/sales/sale_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class DeniedCamera extends MobileScannerPlatform {
  final starting = Completer<MobileScannerViewAttributes>();
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) =>
      starting.future;
  @override
  Future<void> stop() async {}
  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  for (final size in [const Size(360, 760), const Size(760, 360)]) {
    testWidgets('denied camera keeps manual fallback tappable at $size', (
      t,
    ) async {
      final original = MobileScannerPlatform.instance;
      final camera = DeniedCamera();
      MobileScannerPlatform.instance = camera;
      addTearDown(() {
        MobileScannerPlatform.instance = original;
        MobileScannerController.resetPlatformSessionOwner();
        t.view.resetPhysicalSize();
        t.view.resetDevicePixelRatio();
      });
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        MaterialApp(
          theme: appTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const ScannerScreen(),
                  ),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Ouvrir'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(t.takeException(), isNull, reason: "camera loading layout");
      // Torch and permission/lifecycle callbacks can arrive before initialization.
      await t.tap(find.byTooltip("Lampe torche"));
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(t.takeException(), isNull, reason: "camera action error layout");
      camera.starting.completeError(
        const MobileScannerException(
          errorCode: MobileScannerErrorCode.permissionDenied,
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: "camera denial layout");
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Caméra indisponible'), findsOneWidget);
      final fallback = find
          .text('Utiliser la recherche manuelle')
          .hitTestable();
      expect(fallback, findsOneWidget);
      await t.tap(fallback);
      await t.pumpAndSettle();
      expect(find.byType(ScannerScreen), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
