import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../layout/layout.dart';

/// BioBalance colours. Surfaces stay neutral; emerald is reserved for accents.
class Palette {
  const Palette._();

  /// Primary brand — used on CTAs, selected nav, and success meaning.
  static const emerald = Color(0xFF0C6B45);
  static const teal = Color(0xFF0D8F7A);
  static const lime = Color(0xFF7BC96A);
  static const leaf = Color(0xFF4FA85A);

  /// Near-black ink (cool, not green-tinted).
  static const ink = Color(0xFF111318);

  static const amber = Color(0xFFB26A00);
  static const amberSoft = Color(0xFFFFF4E0);
  static const danger = Color(0xFFC0362C);
  static const dangerSoft = Color(0xFFFDECEC);
  static const info = Color(0xFF1C6FB0);
  static const infoSoft = Color(0xFFE8F1FB);
}

/// Colours with a meaning (status, warnings) that the Material scheme does not carry,
/// plus the surfaces of the design (cards, hairlines, shadows).
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.muted,
    required this.mutedSoft,
    required this.card,
    required this.hairline,
    required this.shadow,
    required this.hero,
    required this.onHero,
  });

  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color muted;
  final Color mutedSoft;

  /// The surface of cards, the line around them and their soft shadow.
  final Color card;
  final Color hairline;
  final Color shadow;

  /// The solid surface of the headline cards (today's earnings, what waits, the wallet) and
  /// what is written on it. Deep emerald in both themes: bright mint would glare in the dark.
  final Color hero;
  final Color onHero;

  static const light = StatusColors(
    success: Color(0xFF0C6B45),
    successSoft: Color(0xFFEEF8F3),
    warning: Palette.amber,
    warningSoft: Palette.amberSoft,
    danger: Palette.danger,
    dangerSoft: Palette.dangerSoft,
    info: Palette.info,
    infoSoft: Palette.infoSoft,
    muted: Color(0xFF6B7280),
    mutedSoft: Color(0xFFF3F4F6),
    card: Colors.white,
    hairline: Color(0xFFE6E8EC),
    shadow: Color(0x0A000000),
    hero: Palette.emerald,
    onHero: Colors.white,
  );

  static const dark = StatusColors(
    success: Color(0xFF3DDB97),
    successSoft: Color(0xFF12241C),
    warning: Color(0xFFF2B65C),
    warningSoft: Color(0xFF2E2410),
    danger: Color(0xFFFF8F84),
    dangerSoft: Color(0xFF3A1818),
    info: Color(0xFF8CC5F2),
    infoSoft: Color(0xFF142636),
    muted: Color(0xFF9CA3AF),
    mutedSoft: Color(0xFF1C1E22),
    card: Color(0xFF141518),
    hairline: Color(0xFF2A2C31),
    shadow: Color(0x66000000),
    hero: Color(0xFF0F4A33),
    onHero: Color(0xFFEFFFF6),
  );

  @override
  StatusColors copyWith() => this;

  /// Colours blend while the theme changes (light ↔ dark), like the rest of the theme.
  @override
  StatusColors lerp(StatusColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return StatusColors(
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      muted: c(muted, other.muted),
      mutedSoft: c(mutedSoft, other.mutedSoft),
      card: c(card, other.card),
      hairline: c(hairline, other.hairline),
      shadow: c(shadow, other.shadow),
      hero: c(hero, other.hero),
      onHero: c(onHero, other.onHero),
    );
  }
}

extension ThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  StatusColors get status => Theme.of(this).extension<StatusColors>()!;
}

/// Pages slide up a touch and fade in: quick, soft, the same everywhere.
class _SoftPageTransitions extends PageTransitionsBuilder {
  const _SoftPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: PageFrame(path: route.settings.name, child: child),
      ),
    );
  }
}

/// The system transition of iOS (with the edge swipe back), around the same page frame.
class _ApplePageTransitions extends PageTransitionsBuilder {
  const _ApplePageTransitions();

  static const _cupertino = CupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _cupertino.buildTransitions(
    route,
    context,
    animation,
    secondaryAnimation,
    PageFrame(path: route.settings.name, child: child),
  );
}

/// On a tablet a page keeps a readable width: forms a narrow column, other pages at most
/// [contentMaxWidth], centred. Phones are untouched, and the web console sizes its own pages.
class PageFrame extends StatelessWidget {
  const PageFrame({required this.path, required this.child, super.key});

  /// The route pattern of the page (`/pdvs/:id/edit`), null for the tab shell.
  final String? path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (kIsWeb || path == null || width < wideBreakpoint) return child;
    final max = isFormPath(path!) ? formMaxWidth : contentMaxWidth;
    if (width <= max) return child;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: max),
          child: child,
        ),
      ),
    );
  }
}

class AppTheme {
  const AppTheme._();

  static const radius = 16.0;
  static const _control = 14.0;

  static ThemeData light() => _build(
    ColorScheme.fromSeed(seedColor: Palette.emerald).copyWith(
      primary: Palette.emerald,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFEEF8F3),
      onPrimaryContainer: const Color(0xFF0A3D28),
      secondary: Palette.teal,
      tertiary: Palette.lime,
      surface: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF7F8FA),
      surfaceContainer: const Color(0xFFF1F2F4),
      onSurface: Palette.ink,
      outlineVariant: const Color(0xFFE6E8EC),
      error: Palette.danger,
    ),
    StatusColors.light,
    scaffold: const Color(0xFFF7F8FA),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: Palette.emerald,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF3DDB97),
      onPrimary: const Color(0xFF00301B),
      primaryContainer: const Color(0xFF12241C),
      onPrimaryContainer: const Color(0xFFC7F2DB),
      secondary: const Color(0xFF2BC4AE),
      tertiary: Palette.lime,
      surface: const Color(0xFF141518),
      surfaceContainerLowest: const Color(0xFF0B0C0E),
      surfaceContainerLow: const Color(0xFF16171A),
      surfaceContainer: const Color(0xFF1C1E22),
      onSurface: const Color(0xFFF3F4F6),
      outlineVariant: const Color(0xFF2A2C31),
    ),
    StatusColors.dark,
    scaffold: const Color(0xFF0B0C0E),
  );

  static ThemeData _build(
    ColorScheme scheme,
    StatusColors status, {
    required Color scaffold,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: scaffold,
      extensions: [status],
      // A plain ripple: light on every device, no shader to compile on the first tap.
      splashFactory: InkRipple.splashFactory,
    );
    final control = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_control),
    );
    const buttonText = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 16,
      fontFamily: 'Inter',
      letterSpacing: 0.1,
    );
    final t = base.textTheme;
    return base.copyWith(
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values)
            // iPhone and iPad keep their own slide, and the swipe from the edge to go back.
            p: p == TargetPlatform.iOS || p == TargetPlatform.macOS
                ? const _ApplePageTransitions()
                : const _SoftPageTransitions(),
        },
      ),
      textTheme: t.copyWith(
        displayMedium: t.displayMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
        ),
        headlineMedium: t.headlineMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.8,
        ),
        headlineSmall: t.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
        titleLarge: t.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: t.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
        titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        labelSmall: t.labelSmall?.copyWith(letterSpacing: 0.2),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 20,
        titleTextStyle: t.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.4,
          fontFamily: 'Inter',
        ),
      ),
      cardTheme: CardThemeData(
        color: status.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: status.hairline),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: status.hairline,
        space: 1,
        thickness: 1,
      ),
      // Solid primary — clean and deliberate, no gradient wash on every CTA.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
          shape: WidgetStatePropertyAll(control),
          textStyle: const WidgetStatePropertyAll(buttonText),
          elevation: const WidgetStatePropertyAll(0),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? status.muted
                : scheme.onPrimary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? status.mutedSoft
                : scheme.primary,
          ),
          overlayColor: WidgetStatePropertyAll(
            scheme.onPrimary.withValues(alpha: 0.10),
          ),
          shadowColor: WidgetStatePropertyAll(
            scheme.primary.withValues(alpha: 0.28),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: control,
          side: BorderSide(color: status.hairline),
          backgroundColor: status.card,
          foregroundColor: scheme.onSurface,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: control,
          textStyle: buttonText.copyWith(fontSize: 15),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        highlightElevation: 6,
        extendedTextStyle: buttonText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: status.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_control),
          borderSide: BorderSide(color: status.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_control),
          borderSide: BorderSide(color: status.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_control),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_control),
          borderSide: BorderSide(color: scheme.error),
        ),
        hintStyle: TextStyle(color: status.muted),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: status.hairline),
        backgroundColor: status.card,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
          color: scheme.onSurface,
        ),
        secondaryLabelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
          color: scheme.onPrimaryContainer,
        ),
        selectedColor: scheme.primaryContainer,
        checkmarkColor: scheme.onPrimaryContainer,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(control),
          side: WidgetStatePropertyAll(BorderSide(color: status.hairline)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700, fontFamily: 'Inter'),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : status.card,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
          fontSize: 15,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
          fontSize: 15,
        ),
        unselectedLabelColor: status.muted,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: scheme.primary, width: 2.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: status.mutedSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        // On a big screen a sheet stays a readable column instead of spanning the window.
        constraints: const BoxConstraints(maxWidth: 640),
        backgroundColor: status.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: status.hairline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: status.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: status.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Inter',
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
            letterSpacing: 0.1,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : status.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : status.muted,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }
}
