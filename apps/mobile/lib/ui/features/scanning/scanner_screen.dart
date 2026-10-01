import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/design.dart';
import '../../core/navigation.dart';
import 'scanner_view_model.dart';

class ScannerScreen extends StatefulWidget {
  final String title, hint, manualLabel;
  const ScannerScreen({
    super.key,
    this.title = 'Scanner un code-barres',
    this.manualLabel = 'Utiliser la recherche manuelle',
    this.hint =
        'Placez le code-barres dans le cadre. Rapprochez-vous si nécessaire.',
  });
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with WidgetsBindingObserver {
  final vm = ScannerViewModel();
  bool current = false;
  bool foreground =
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    current = ModalRoute.isCurrentOf(context) ?? true;
    // Attach the preview before starting and let the route frame render first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) vm.setActive(current && foreground);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The permission dialog only makes the app inactive: the camera must not be
    // stopped and restarted underneath it.
    foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    vm.setActive(current && foreground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        ValueListenableBuilder(
          valueListenable: vm.controller,
          builder: (_, state, _) => IconButton(
            onPressed:
                state.isRunning && state.torchState != TorchState.unavailable
                ? vm.toggleTorch
                : null,
            isSelected: state.torchState == TorchState.on,
            icon: const Icon(AppIcons.flashlightOnOutlined),
            selectedIcon: const Icon(AppIcons.flashlightOn),
            tooltip: 'Lampe torche',
          ),
        ),
      ],
    ),
    body: LayoutBuilder(
      builder: (context, constraints) => Flex(
        direction: constraints.maxWidth > constraints.maxHeight
            ? Axis.horizontal
            : Axis.vertical,
        children: [
          Expanded(
            flex: 3,
            child: RepaintBoundary(
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final size = constraints.biggest;
                  final frame = Rect.fromCenter(
                    center: size.center(Offset.zero),
                    width: math.min(480, size.width * .9),
                    height: math.min(240, size.height * .7),
                  );
                  return MobileScanner(
                    controller: vm.controller,
                    useAppLifecycleState: false,
                    placeholderBuilder: (_) => const ColoredBox(
                      color: Colors.black,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    overlayBuilder: (_, _) => IgnorePointer(
                      child: Stack(
                        children: [
                          Positioned.fromRect(
                            rect: frame,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    errorBuilder: (_, _) => const SingleChildScrollView(
                      child: EmptyState(
                        title: 'Caméra indisponible',
                        description: 'Autorisez la caméra dans les réglages ou utilisez la recherche manuelle.',
                        icon: AppIcons.noPhotographyOutlined,
                      ),
                    ),
                    onDetect: (capture) {
                      final code = vm.accept(
                        capture.barcodes.map((b) => b.rawValue),
                      );
                      if (code == null) return;
                      unawaited(
                        HapticFeedback.selectionClick().catchError(
                          (Object _) {},
                        ),
                      );
                      completeRoute(context, code);
                    },
                  );
                },
              ),
            ),
          ),
          Flexible(
            flex: 2,
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ListenableBuilder(
                  listenable: vm,
                  builder: (_, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () {
                          vm.setActive(false);
                          Navigator.pop(context);
                        },
                        child: Text(widget.manualLabel),
                      ),
                      Text(vm.error ?? widget.hint),
                      if (vm.error != null)
                        TextButton(
                          onPressed: vm.retry,
                          child: const Text('Réessayer la caméra'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
