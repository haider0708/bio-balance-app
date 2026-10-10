import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/brand/leaf_mark.dart';
import '../../core/theme/app_theme.dart';

/// True once the opening animation has played: until then the app stays on the splash, even
/// when the session is already known, so the animation is never cut in the middle.
class SplashDone extends Notifier<bool> {
  @override
  bool build() => false;

  void finish() => state = true;
}

final splashDoneProvider = NotifierProvider<SplashDone, bool>(SplashDone.new);

/// The width of the mark, the same as on the system launch screen so nothing jumps.
const _markWidth = 128.0;

/// The opening: the leaf drops into water (a dip, ripples, a shine), the name appears letter by
/// letter, and bubbles rise behind. It plays once per start; with reduced motion it is a still.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro;
  late final AnimationController _bubbles = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  late final List<_Bubble> _field = _Bubble.field(28);
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // The browser console is reloaded often: a shorter opening there.
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kIsWeb ? 1100 : 1900),
    );
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        ref.read(splashDoneProvider.notifier).finish();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _intro.duration = const Duration(milliseconds: 400);
    } else {
      _bubbles.repeat();
    }
    _intro.forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _bubbles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final still = MediaQuery.of(context).disableAnimations;
    final background = dark ? const Color(0xFF0B0C0E) : Colors.white;
    final water = dark ? const Color(0xFF3DDB97) : Palette.emerald;
    return Scaffold(
      backgroundColor: background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!still)
            RepaintBoundary(
              child: CustomPaint(
                painter: _BubblesPainter(
                  bubbles: _field,
                  time: _bubbles,
                  appear: _intro,
                  color: water,
                ),
              ),
            ),
          AnimatedBuilder(
            animation: _intro,
            builder: (context, _) {
              final t = still ? 1.0 : _intro.value;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: CustomPaint(
                      painter: _RipplesPainter(t: t, color: water),
                      child: Transform.scale(
                        scale: _dip.transform(t),
                        child: LeafMarkView(
                          width: _markWidth,
                          shine: _interval(t, 0.38, 0.8),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: _markWidth * LeafMark.aspect + 64,
                      ),
                      // The name always fits, whatever the screen or text size.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _Name(t: t, dark: dark),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// The leaf's movement: a small dip as it touches the water, a bounce, then rest.
final _dip = TweenSequence<double>([
  TweenSequenceItem(
    tween: Tween(begin: 1.0, end: 0.9).chain(CurveTween(curve: Curves.easeOut)),
    weight: 18,
  ),
  TweenSequenceItem(
    tween: Tween(
      begin: 0.9,
      end: 1.07,
    ).chain(CurveTween(curve: Curves.easeOutCubic)),
    weight: 20,
  ),
  TweenSequenceItem(
    tween: Tween(
      begin: 1.07,
      end: 1.0,
    ).chain(CurveTween(curve: Curves.easeInOut)),
    weight: 22,
  ),
  TweenSequenceItem(tween: ConstantTween(1.0), weight: 40),
]);

/// Where [t] is between [from] and [to], from 0 to 1 (clamped).
double _interval(double t, double from, double to) =>
    ((t - from) / (to - from)).clamp(0.0, 1.0);

/// "BioBalance" letter by letter, then "BACK TO NATURE".
class _Name extends StatelessWidget {
  const _Name({required this.t, required this.dark});

  final double t;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    const word = 'BioBalance';
    final ink = dark ? const Color(0xFFF3F4F6) : Palette.ink;
    final style = context.text.headlineMedium?.copyWith(
      color: ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
    );
    final tagline = Curves.easeOut.transform(_interval(t, 0.72, 1));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: word,
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < word.length; i++)
                  Builder(
                    builder: (context) {
                      final start = 0.42 + i * 0.03;
                      final k = Curves.easeOutCubic.transform(
                        _interval(t, start, start + 0.22),
                      );
                      return Opacity(
                        opacity: k,
                        child: Transform.translate(
                          offset: Offset(0, 10 * (1 - k)),
                          child: Text(word[i], style: style),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Opacity(
          opacity: tagline,
          child: Text(
            'BACK TO NATURE',
            style: context.text.labelMedium?.copyWith(
              color: (dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280)),
              letterSpacing: 4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Two rings spreading from the leaf as it touches the water.
class _RipplesPainter extends CustomPainter {
  const _RipplesPainter({required this.t, required this.color});

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (final start in const [0.14, 0.28]) {
      final k = _interval(t, start, start + 0.55);
      if (k <= 0 || k >= 1) continue;
      final eased = Curves.easeOutCubic.transform(k);
      canvas.drawCircle(
        center,
        _markWidth * (0.45 + 1.25 * eased),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - k) + 0.5
          ..color = color.withValues(alpha: 0.32 * (1 - k)),
      );
    }
  }

  @override
  bool shouldRepaint(_RipplesPainter old) => old.t != t || old.color != color;
}

/// One bubble: where it starts, how big, how fast, how it sways.
class _Bubble {
  const _Bubble(this.x, this.radius, this.speed, this.phase, this.sway);

  final double x;
  final double radius;
  final double speed;
  final double phase;
  final double sway;

  /// The same scattering at every start (a fixed seed): calm, never crowded.
  static List<_Bubble> field(int count) {
    final random = math.Random(7);
    return [
      for (var i = 0; i < count; i++)
        _Bubble(
          random.nextDouble(),
          3 + math.pow(random.nextDouble(), 2.2) * 19,
          0.05 + random.nextDouble() * 0.09,
          random.nextDouble(),
          6 + random.nextDouble() * 14,
        ),
    ];
  }
}

/// Bubbles rising through the screen: a soft body, a brighter rim and a glint, fading out as
/// they near the top.
class _BubblesPainter extends CustomPainter {
  _BubblesPainter({
    required this.bubbles,
    required this.time,
    required this.appear,
    required this.color,
  }) : super(repaint: Listenable.merge([time, appear]));

  final List<_Bubble> bubbles;
  final Animation<double> time;

  /// The opening: bubbles fade in with it, so the first frame matches the launch screen.
  final Animation<double> appear;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = time.value * 12;
    for (final b in bubbles) {
      // Bigger bubbles rise a little faster, like real ones.
      final travel =
          (b.phase + seconds * b.speed * (0.7 + b.radius / 40)) % 1.0;
      final y = size.height * (1.08 - travel * 1.2);
      final x =
          size.width * b.x +
          math.sin((seconds * 1.3 + b.phase * 6.28) + travel * 4) * b.sway;
      final fade =
          (travel < 0.15 ? travel / 0.15 : 1.0) *
          (travel > 0.75 ? (1 - travel) / 0.25 : 1.0);
      if (fade <= 0) continue;
      final center = Offset(x, y);
      final r = b.radius;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.3, -0.35),
            colors: [
              color.withValues(alpha: 0.02 * fade),
              color.withValues(alpha: 0.10 * fade),
              color.withValues(alpha: 0.22 * fade),
            ],
            stops: const [0.0, 0.75, 1.0],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r > 10 ? 1.2 : 0.8
          ..color = color.withValues(alpha: 0.28 * fade),
      );
      canvas.drawCircle(
        center + Offset(-r * 0.38, -r * 0.38),
        r * 0.22,
        Paint()..color = Colors.white.withValues(alpha: 0.75 * fade),
      );
    }
  }

  @override
  bool shouldRepaint(_BubblesPainter old) =>
      old.color != color || old.bubbles != bubbles;
}
