import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A white rounded panel. Tappable when [onTap] is set.
class AppCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final card = Card(
      color: color,
      shape: borderColor == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: borderColor!),
            ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(14), onTap: onTap, child: card),
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
      padding: padding ?? const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.titleMedium)),
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
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: colors.soft, borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 16, color: colors.strong),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  label,
                  style: context.text.bodySmall?.copyWith(color: context.status.muted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: context.text.headlineSmall?.copyWith(color: tone == Tone.neutral ? null : colors.strong)),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(hint!, style: context.text.bodySmall?.copyWith(color: context.status.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
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
      Tone.neutral => (strong: context.colors.primary, soft: context.colors.primaryContainer),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.soft, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: c.strong), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              style: context.text.labelSmall?.copyWith(color: c.strong, fontWeight: FontWeight.w700),
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
  const Avatar(this.initials, {this.size = 44, this.tone = Tone.neutral, super.key});

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
      decoration: BoxDecoration(color: c.soft, shape: BoxShape.circle),
      child: Text(initials, style: TextStyle(color: c.strong, fontWeight: FontWeight.w700, fontSize: size * 0.36)),
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
          Expanded(flex: 4, child: Text(label, style: context.text.bodyMedium?.copyWith(color: context.status.muted))),
          Expanded(flex: 6, child: Text(value, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.end)),
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
        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[Icon(widget.icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(widget.label, overflow: TextOverflow.ellipsis)),
            ],
          );
    final button = switch (widget.style) {
      AsyncButtonStyle.filled => FilledButton(onPressed: onPressed, child: child),
      AsyncButtonStyle.outlined => OutlinedButton(onPressed: onPressed, child: child),
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
    return widget.expanded ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// Space between stacked blocks of a screen.
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}
