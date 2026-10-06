import 'dart:math';

import 'package:flutter/material.dart';

/// A short burst of coloured paper for the "Bravo" screen. Purely decorative, ignores taps.
class ConfettiBurst extends StatefulWidget {
  const ConfettiBurst({required this.colors, super.key});

  final List<Color> colors;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..forward();
  late final List<_Piece> _pieces;

  @override
  void initState() {
    super.initState();
    final random = Random(7);
    _pieces = List.generate(
      70,
      (_) => _Piece(
        angle: -pi / 2 + (random.nextDouble() - 0.5) * pi * 1.1,
        speed: 260 + random.nextDouble() * 520,
        size: 6 + random.nextDouble() * 7,
        spin: (random.nextDouble() - 0.5) * 14,
        color: widget.colors[random.nextInt(widget.colors.length)],
        round: random.nextBool(),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce) return const SizedBox.shrink();
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _ConfettiPainter(_pieces, _controller.value),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.angle,
    required this.speed,
    required this.size,
    required this.spin,
    required this.color,
    required this.round,
  });

  final double angle;
  final double speed;
  final double size;
  final double spin;
  final Color color;
  final bool round;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.pieces, this.t);

  final List<_Piece> pieces;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.34);
    final time = t * 2.6;
    for (final p in pieces) {
      final x = origin.dx + cos(p.angle) * p.speed * time * 0.55;
      final y =
          origin.dy +
          sin(p.angle) * p.speed * time * 0.55 +
          520 * time * time * 0.5;
      final fade = (1 - ((t - 0.65) / 0.35)).clamp(0.0, 1.0);
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * time);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: p.size,
              height: p.size * 0.6,
            ),
            const Radius.circular(1.5),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
