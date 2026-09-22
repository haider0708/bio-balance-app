import 'dart:math' as math;

import 'package:flutter/material.dart';

const brandGreen = Color(0xFF6ABE4E);
const darkGreen = Color(0xFF286B34);
const ink = Color(0xFF161C18);
const muted = Color(0xFF606164);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Inter',
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: darkGreen,
    primary: darkGreen,
    surface: Colors.white,
    onSurface: ink,
    primaryContainer: const Color(0xFFEAF6E5),
    onPrimaryContainer: darkGreen,
    error: const Color(0xFFAF342C),
  ),
  scaffoldBackgroundColor: Colors.white,
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.45),
    bodyMedium: TextStyle(fontSize: 16, color: ink, height: 1.4),
    bodySmall: TextStyle(fontSize: 14, color: muted, height: 1.4),
    titleLarge: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    foregroundColor: ink,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFDDE3D9)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFDDE3D9)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: brandGreen,
      foregroundColor: ink,
      minimumSize: const Size(48, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  cardTheme: CardThemeData(
    color: Colors.white,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: Color(0xFFE5E9E1)),
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    indicatorColor: Color(0xFFE4F5DC),
    labelPadding: EdgeInsets.zero,
    labelTextStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: 14, letterSpacing: -0.3, fontWeight: FontWeight.w500),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
  ),
  listTileTheme: const ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    minVerticalPadding: 8,
    minLeadingWidth: 24,
    horizontalTitleGap: 12,
  ),
  dividerTheme: const DividerThemeData(color: Color(0xFFE5E9E1), space: 1),
);

class Content extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;
  final IndexedWidgetBuilder? itemBuilder;
  final int itemCount;
  const Content({super.key, required this.children, this.maxWidth = 1100})
    : itemBuilder = null,
      itemCount = 0;
  const Content.builder({
    super.key,
    this.children = const [],
    this.maxWidth = 1100,
    required this.itemCount,
    required this.itemBuilder,
  });
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: children.length + itemCount,
        itemBuilder: (context, index) => index < children.length
            ? children[index]
            : itemBuilder!(context, index - children.length),
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;
  const SectionTitle(this.title, {super.key, this.subtitle, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16, top: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            ?action,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  final String title, description;
  final IconData icon;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.title,
    required this.description,
    this.icon = Icons.inbox_outlined,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
    child: Column(
      children: [
        Icon(icon, size: 32, color: muted),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          description,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

class Notice extends StatelessWidget {
  final String message;
  final IconData icon;
  final bool error;
  final VoidCallback? retry;
  const Notice(
    this.message, {
    super.key,
    this.icon = Icons.info_outline,
    this.error = false,
    this.retry,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFBECE9) : const Color(0xFFEBF5E7),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: error ? const Color(0xFFAF342C) : darkGreen),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message, style: Theme.of(context).textTheme.bodySmall),
        ),
        if (retry != null)
          IconButton(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            tooltip: 'Réessayer',
          ),
      ],
    ),
  );
}

enum AppTone {
  success(Color(0xFF286B34), Color(0xFFEAF6E5)),
  info(Color(0xFF185D91), Color(0xFFEAF4FD)),
  warning(Color(0xFF88500A), Color(0xFFFFF3DC)),
  danger(Color(0xFFAF342C), Color(0xFFFBECE9)),
  reward(Color(0xFF7140A4), Color(0xFFF3EBFB));

  const AppTone(this.foreground, this.background);
  final Color foreground, background;
}

class StatusChip extends StatelessWidget {
  final String text;
  final IconData icon;
  final AppTone tone;
  const StatusChip(
    this.text, {
    super.key,
    this.icon = Icons.check_circle_outline,
    this.tone = AppTone.success,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: tone.background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Icon(icon, size: 18, color: tone.foreground),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tone.foreground),
        ),
      ],
    ),
  );
}

/// A single short transition when a destination changes. No retained outgoing
/// store page, background loop, blur, or animation on synchronization updates.
class PageEntrance extends StatefulWidget {
  final Widget child;
  const PageEntrance({super.key, required this.child});
  @override
  State<PageEntrance> createState() => _PageEntranceState();
}

class _PageEntranceState extends State<PageEntrance>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  late final animation = CurvedAnimation(
    parent: controller,
    curve: Curves.easeOutCubic,
  );
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      controller.value = 1;
      started = true;
    } else if (!started) {
      started = true;
      controller.forward();
    }
  }

  @override
  void dispose() {
    animation.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, .015),
        end: Offset.zero,
      ).animate(animation),
      child: widget.child,
    ),
  );
}

/// Flat, readable collection row shared by operational screens. Value text
/// moves below the title at large text scales; actions retain 48 dp targets.
class CompactRow extends StatelessWidget {
  final String title;
  final String? subtitle, value;
  final IconData? icon;
  final Widget? leading, trailing, footer;
  final VoidCallback? onTap;
  final bool selected;
  final AppTone tone;
  const CompactRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.leading,
    this.trailing,
    this.footer,
    this.onTap,
    this.selected = false,
    this.tone = AppTone.success,
  });
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stackedValue =
          constraints.maxWidth < 300 ||
          MediaQuery.textScalerOf(context).scale(16) > 22;
      final valueText = value == null
          ? null
          : Text(
              value!,
              style: const TextStyle(fontWeight: FontWeight.w600, color: ink),
            );
      return Material(
        color: selected ? const Color(0xFFF2F7F0) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE8ECE6))),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null || icon != null) ...[
                  leading ??
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: tone.background,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 22, color: tone.foreground),
                      ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (stackedValue && valueText != null) ...[
                        const SizedBox(height: 4),
                        valueText,
                      ],
                      if (footer != null) ...[
                        const SizedBox(height: 6),
                        footer!,
                      ],
                    ],
                  ),
                ),
                if (!stackedValue && valueText != null) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * .38,
                    ),
                    child: valueText,
                  ),
                ],
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ] else if (onTap != null) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, size: 20, color: muted),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}

class MetricStrip extends StatelessWidget {
  final List<({String label, String value})> metrics;
  const MetricStrip({super.key, required this.metrics});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (metrics.isEmpty) return const SizedBox.shrink();
      final scaler = MediaQuery.textScalerOf(context);
      final valueStyle = Theme.of(context).textTheme.titleLarge!
          .copyWith(fontSize: 20);
      final labelStyle = Theme.of(context).textTheme.bodySmall!;
      double measured(String text, TextStyle style) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      final minimum = metrics.fold<double>(
        scaler.scale(96),
        (width, metric) => math.max(
          width,
          math.max(
                measured(metric.value, valueStyle),
                measured(metric.label, labelStyle),
              ) +
              12,
        ),
      );
      final available = math.max(0.0, constraints.maxWidth - 2);
      final columns = (available / minimum).floor().clamp(1, metrics.length);
      final width = (available / columns).floorToDouble();
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5FAF2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4EEDD)),
        ),
        child: Wrap(
          children: [
            for (final metric in metrics)
              SizedBox(
                width: width,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(metric.value, style: valueStyle),
                      const SizedBox(height: 2),
                      Text(
                        metric.label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class BottomAction extends StatelessWidget {
  final Widget child;
  const BottomAction({super.key, required this.child});
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8ECE6))),
      ),
      child: Align(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    ),
  );
}
