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

/// Gold coins falling from the top while the reward counts up. Decorative, ignores taps.
class CoinRain extends StatefulWidget {
  const CoinRain({super.key});

  @override
  State<CoinRain> createState() => _CoinRainState();
}

class _CoinRainState extends State<CoinRain>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  )..forward();
  late final List<
    ({double x, double delay, double speed, double size, double spin})
  >
  _coins = () {
    final random = Random(11);
    return List.generate(
      18,
      (_) => (
        x: random.nextDouble(),
        delay: random.nextDouble() * 0.45,
        speed: 0.75 + random.nextDouble() * 0.5,
        size: 18 + random.nextDouble() * 12,
        spin: 2 + random.nextDouble() * 4,
      ),
    );
  }();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations)
      return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) => AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Stack(
            children: [
              for (final c in _coins)
                Builder(
                  builder: (context) {
                    final t = ((_controller.value - c.delay) / (1 - c.delay))
                        .clamp(0.0, 1.0);
                    if (t == 0 || t == 1) return const SizedBox.shrink();
                    final y =
                        -40 + (box.maxHeight + 80) * pow(t, 1.4) * c.speed;
                    final flip = cos(t * c.spin * pi).abs().clamp(0.15, 1.0);
                    return Positioned(
                      left: c.x * (box.maxWidth - c.size),
                      top: y,
                      child: Opacity(
                        opacity: (1 - pow(t, 6)).toDouble(),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.diagonal3Values(flip, 1, 1),
                          child: Container(
                            width: c.size,
                            height: c.size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const RadialGradient(
                                colors: [Color(0xFFFFE08A), Color(0xFFE5A800)],
                              ),
                              border: Border.all(
                                color: const Color(0xFFB88200),
                                width: 1.5,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: c.size * 0.5,
                                height: c.size * 0.5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFB88200),
                                    width: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
