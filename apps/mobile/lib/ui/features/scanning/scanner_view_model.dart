import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Owns one camera session. Native transitions are serialized, including a
/// permission result arriving after the screen has closed or gone inactive.
class ScannerViewModel extends ChangeNotifier {
  final MobileScannerController controller;
  ScannerViewModel({MobileScannerController? controller})
    : controller =
          controller ??
          MobileScannerController(
            autoStart: false,
            detectionSpeed: DetectionSpeed.normal,
            detectionTimeoutMs: 250,
            cameraResolution: const Size(640, 480),
            returnImage: false,
            invertImage: false,
            autoZoom: false,
          );

  Future<void> _tail = Future.value();
  bool _active = false, _captured = false, _closed = false;
  String? error;

  bool get _shouldRun => _active && !_captured && !_closed;

  void setActive(bool active) {
    if (_closed || _active == active) return;
    _active = active;
    _enqueue(_reconcile);
  }

  void retry() {
    if (_shouldRun) _enqueue(_reconcile);
  }

  void _enqueue(Future<void> Function() action) {
    _tail = _tail.then((_) async {
      try {
        await action();
      } catch (_) {
        if (!_closed) {
          error = 'Caméra indisponible. Vous pouvez rechercher le produit.';
          notifyListeners();
        }
      }
    });
  }

  Future<void> _reconcile() async {
    // Read the latest intent here, not the state when this action was queued.
    // No restart is allowed after a capture or while closing the route.
    if (_shouldRun) {
      if (!controller.value.isRunning) await controller.start();
      if (!_closed) {
        error = controller.value.error == null
            ? null
            : 'Caméra indisponible. Vérifiez l’autorisation dans les réglages.';
        notifyListeners();
      }
    }
    if (!_shouldRun) await controller.stop();
  }

  String? accept(Iterable<String?> codes) {
    if (!_shouldRun || !controller.value.isRunning || error != null) {
      return null;
    }
    for (final value in codes) {
      final code = value?.trim();
      if (code == null || code.isEmpty) continue;
      _captured =
          true; // Synchronous latch: queued camera frames cannot repeat.
      _enqueue(_reconcile);
      return code;
    }
    return null;
  }

  void detectionFailed() {
    if (_closed) return;
    error = 'Lecture interrompue. Réessayez ou recherchez le produit.';
    _enqueue(controller.stop);
    notifyListeners();
  }

  void toggleTorch() {
    _enqueue(() async {
      if (_shouldRun && controller.value.isRunning) {
        await controller.toggleTorch();
      }
    });
  }

  @override
  void dispose() {
    _closed = true;
    _enqueue(() async {
      try {
        await controller.stop();
      } finally {
        await controller.dispose();
      }
    });
    super.dispose();
  }
}
