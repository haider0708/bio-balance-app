import 'package:flutter/widgets.dart';

import 'leaf_mark_data.dart';

/// The BioBalance leaf mark as vector paths, drawn sharp at any size and easy to animate.
class LeafMark {
  const LeafMark._();

  static final Path leaf = _parse(leafMarkLeaf);
  static final Path veins = _parse(leafMarkVeins);

  /// Height over width of the mark.
  static const aspect = leafMarkHeight / leafMarkWidth;

  static Path _parse(String d) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final m in RegExp(r'([MLCZ])([^MLCZ]*)').allMatches(d)) {
      final n = [
        for (final v in RegExp(r'-?[\d.]+').allMatches(m.group(2)!))
          double.parse(v.group(0)!),
      ];
      switch (m.group(1)) {
        case 'M':
          path.moveTo(n[0], n[1]);
        case 'L':
          path.lineTo(n[0], n[1]);
        case 'C':
          path.cubicTo(n[0], n[1], n[2], n[3], n[4], n[5]);
        default:
          path.close();
      }
    }
    return path;
  }
}

/// Paints the mark into its box; [shine] (0 → 1) sweeps a soft light across the leaves.
class LeafMarkPainter extends CustomPainter {
  const LeafMarkPainter({this.shine});

  final double? shine;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / leafMarkWidth);
    canvas.drawPath(
      LeafMark.leaf,
      Paint()..color = const Color(leafMarkLeafColor),
    );
    canvas.drawPath(
      LeafMark.veins,
      Paint()..color = const Color(leafMarkVeinColor),
    );
    final s = shine;
    if (s != null && s > 0 && s < 1) {
      // A diagonal band of light that crosses the leaves once.
      final x = -leafMarkWidth * 0.6 + s * leafMarkWidth * 2.2;
      canvas.save();
      canvas.clipPath(LeafMark.leaf);
      canvas.drawRect(
        const Offset(0, 0) & const Size(leafMarkWidth, leafMarkHeight),
        Paint()
          ..shader =
              LinearGradient(
                colors: const [
                  Color(0x00FFFFFF),
                  Color(0x66FFFFFF),
                  Color(0x00FFFFFF),
                ],
                stops: const [0.35, 0.5, 0.65],
                transform: _Shift(x),
              ).createShader(
                const Offset(0, 0) & const Size(leafMarkWidth, leafMarkHeight),
              ),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LeafMarkPainter old) => old.shine != shine;
}

/// Moves a gradient sideways (and tilts it), for the shine.
class _Shift extends GradientTransform {
  const _Shift(this.dx);

  final double dx;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.identity()
        ..translateByDouble(dx, 0, 0, 1)
        ..rotateZ(-0.35);
}

/// The mark at a given width.
class LeafMarkView extends StatelessWidget {
  const LeafMarkView({required this.width, this.shine, super.key});

  final double width;
  final double? shine;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'BioBalance',
    image: true,
    child: CustomPaint(
      size: Size(width, width * LeafMark.aspect),
      painter: LeafMarkPainter(shine: shine),
    ),
  );
}

/// The leaf on a white rounded tile, like the app icon: the brand next to the name in the
/// console's sidebar and sign-in page.
class LeafMarkTile extends StatelessWidget {
  const LeafMarkTile({this.size = 36, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(size * 0.28),
    ),
    // The name is written next to it: read once, not twice.
    child: ExcludeSemantics(child: LeafMarkView(width: size * 0.7)),
  );
}
