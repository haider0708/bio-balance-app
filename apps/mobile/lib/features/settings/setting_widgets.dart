import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A setting you switch on or off: a title, what it does under it, the switch at the end. The whole
/// row is the target, so the switch is never the only thing to hit.
class SettingSwitch extends StatelessWidget {
  const SettingSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.leading,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final bool value;

  /// Null shows it disabled.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: title,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? () => onChanged!(!value) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              spacing: 12,
              children: [
                ?leading,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: context.text.titleSmall?.copyWith(
                          color: enabled ? null : context.status.muted,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: context.text.bodySmall?.copyWith(
                            color: context.status.muted,
                          ),
                        ),
                    ],
                  ),
                ),
                ExcludeSemantics(
                  child: Switch(value: value, onChanged: onChanged),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rows in one rounded, hairline-bordered block, a line between each.
class SettingGroup extends StatelessWidget {
  const SettingGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: s.hairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: children[i],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A time shown in a box you tap to change.
class TimeBox extends StatelessWidget {
  const TimeBox(this.time, {required this.onTap, super.key});

  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.status;
    return Material(
      color: s.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: s.hairline),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 68, minHeight: 40),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            time,
            style: context.text.titleSmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
