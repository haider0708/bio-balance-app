import 'package:flutter/material.dart';

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

  /// Subtle brand wash for rare hero surfaces (wallet, today card).
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0C6B45), Color(0xFF0D8F7A)],
  );
  static const brandDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1FA971), Color(0xFF1BB39C)],
  );
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
    required this.gradient,
    required this.glow,
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

  /// Brand gradient for rare hero accents (not page backgrounds).
  final LinearGradient gradient;

  /// Kept for API compatibility; intentionally near-transparent / neutral.
  final Color glow;

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
    gradient: Palette.brand,
    glow: Color(0x00FFFFFF),
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
    gradient: Palette.brandDark,
    glow: Color(0x00000000),
  );

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(StatusColors? other, double t) =>
      t < 0.5 ? this : (other ?? this);
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
        child: child,
      ),
    );
  }
}

class AppTheme {
  const AppTheme._();

  static const radius = 16.0;
  static const _control = 14.0;

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: Palette.emerald,
      brightness: Brightness.light,
    ).copyWith(
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
      splashFactory: InkSparkle.splashFactory,
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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _SoftPageTransitions(),
          TargetPlatform.iOS: _SoftPageTransitions(),
          TargetPlatform.linux: _SoftPageTransitions(),
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
          side: BorderSide(color: status.hairline, width: 1),
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
