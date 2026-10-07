import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The basic surface: a rounded card with a hairline and a soft shadow. When it can be
/// tapped it sinks a little under the finger.
class AppCard extends StatefulWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _down = false;

  void _press(bool down) {
    if (widget.onTap != null && _down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    final radius = BorderRadius.circular(AppTheme.radius);
    final flat = widget.color != null;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: widget.color ?? s.card,
        borderRadius: radius,
        border: Border.all(color: widget.borderColor ?? s.hairline),
        boxShadow: flat
            ? null
            : [
                BoxShadow(
                  color: s.shadow,
                  blurRadius: _down ? 6 : 18,
                  offset: Offset(0, _down ? 1 : 5),
                ),
              ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.onTap,
          onHighlightChanged: _press,
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
    if (widget.onTap == null) return card;
    return AnimatedScale(
      scale: _down ? 0.985 : 1,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      child: card,
    );
  }
}

/// A square badge holding an icon, tinted by tone (or filled with the brand gradient).
class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon, {
    this.tone = Tone.neutral,
    this.size = 40,
    this.gradient = false,
    super.key,
  });

  final IconData icon;
  final Tone tone;
  final double size;
  final bool gradient;

  @override
  Widget build(BuildContext context) {
    final c = tone.colors(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: gradient ? null : c.soft,
        gradient: gradient ? context.status.gradient : null,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(
        icon,
        size: size * 0.5,
        color: gradient ? context.colors.onPrimary : c.strong,
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.trailing, this.padding, super.key});

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(4, 26, 4, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: context.text.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// A number with a label: the building block of dashboards.
class StatTile extends StatelessWidget {
  const StatTile({
    required this.label,
    required this.value,
    this.icon,
    this.hint,
    this.tone = Tone.neutral,
    this.onTap,
    super.key,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? hint;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = tone.colors(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                IconBadge(icon!, tone: tone, size: 30),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label,
                  style: context.text.bodySmall?.copyWith(
                    color: context.status.muted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: CountUpText(
              value,
              style: context.text.headlineSmall?.copyWith(
                color: tone == Tone.neutral ? null : colors.strong,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              style: context.text.bodySmall?.copyWith(
                color: context.status.muted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

enum Tone {
  neutral,
  success,
  warning,
  danger,
  info,
  muted;

  ({Color strong, Color soft}) colors(BuildContext context) {
    final s = context.status;
    return switch (this) {
      Tone.success => (strong: s.success, soft: s.successSoft),
      Tone.warning => (strong: s.warning, soft: s.warningSoft),
      Tone.danger => (strong: s.danger, soft: s.dangerSoft),
      Tone.info => (strong: s.info, soft: s.infoSoft),
      Tone.muted => (strong: s.muted, soft: s.mutedSoft),
      Tone.neutral => (
        strong: context.colors.primary,
        soft: context.colors.primaryContainer,
      ),
    };
  }
}

/// A small coloured pill: statuses, counts, roles.
class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {this.tone = Tone.muted, this.icon, super.key});

  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = tone.colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.soft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c.strong),
            const SizedBox(width: 4),
          ] else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: c.strong,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: context.text.labelSmall?.copyWith(
                color: c.strong,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(
    this.initials, {
    this.size = 44,
    this.tone = Tone.neutral,
    super.key,
  });

  final String initials;
  final double size;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final c = tone.colors(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tone == Tone.neutral ? null : c.soft,
        gradient: tone == Tone.neutral ? context.status.gradient : null,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: tone == Tone.neutral ? context.colors.onPrimary : c.strong,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}

/// A label and its value on one line.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: context.text.bodyMedium?.copyWith(
                color: context.status.muted,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: context.text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

/// A button that shows progress and ignores taps while its action runs.
class AsyncButton extends StatefulWidget {
  const AsyncButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = AsyncButtonStyle.filled,
    this.expanded = true,
    super.key,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;
  final AsyncButtonStyle style;
  final bool expanded;

  @override
  State<AsyncButton> createState() => _AsyncButtonState();
}

enum AsyncButtonStyle { filled, outlined, danger, text }

class _AsyncButtonState extends State<AsyncButton> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy || widget.onPressed == null) return;
    setState(() => _busy = true);
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = widget.onPressed == null || _busy ? null : _run;
    final child = _busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(widget.label, overflow: TextOverflow.ellipsis),
              ),
            ],
          );
    final button = switch (widget.style) {
      AsyncButtonStyle.filled => FilledButton(
        onPressed: onPressed,
        child: child,
      ),
      AsyncButtonStyle.outlined => OutlinedButton(
        onPressed: onPressed,
        child: child,
      ),
      AsyncButtonStyle.text => TextButton(onPressed: onPressed, child: child),
      AsyncButtonStyle.danger => FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: context.status.danger,
          foregroundColor: context.colors.surface,
        ),
        child: child,
      ),
    };
    return widget.expanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

/// Space between stacked blocks of a screen.
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

/// Text that counts up to its number the first time it appears ("1 240 units", "45.500 TND").
/// Anything without digits is shown as is.
class CountUpText extends StatelessWidget {
  const CountUpText(this.text, {this.style, super.key});

  final String text;
  final TextStyle? style;

  static final _number = RegExp(r'\d[\d\s.,]*');

  @override
  Widget build(BuildContext context) {
    final match = _number.firstMatch(text);
    if (match == null || MediaQuery.of(context).disableAnimations) {
      return Text(text, style: style);
    }
    final raw = match.group(0)!;
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    final target = int.tryParse(digits);
    if (target == null || target == 0 || digits.length > 12) {
      return Text(text, style: style);
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey(text),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        if (v >= 1) return Text(text, style: style);
        // Rebuild the number with the same separators, digit by digit.
        final now = (target * v).round().toString().padLeft(digits.length, '0');
        var i = 0;
        final shown = raw.split('').map((ch) {
          if (RegExp(r'\d').hasMatch(ch)) return now[i++];
          return ch;
        }).join();
        final trimmed = shown.replaceFirst(RegExp(r'^[0\s.,]+(?=\d)'), '');
        return Text(text.replaceFirst(raw, trimmed), style: style);
      },
    );
  }
}

/// Grey blocks that pulse while a screen loads: the layout appears before the data.
class Skeleton extends StatefulWidget {
  const Skeleton({this.rows = 5, super.key});

  final int rows;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    Widget block(double h, {double? w}) => Container(
      height: h,
      width: w,
      decoration: BoxDecoration(
        color: s.mutedSoft,
        borderRadius: BorderRadius.circular(12),
      ),
    );
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_pulse),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Row(
            children: [
              Expanded(child: block(96)),
              const SizedBox(width: 12),
              Expanded(child: block(96)),
            ],
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < widget.rows; i++) ...[
            Row(
              children: [
                block(48, w: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      block(14, w: 180),
                      const SizedBox(height: 8),
                      block(12, w: 110),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
          ],
        ],
      ),
    );
  }
}
