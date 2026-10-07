import 'package:flutter/material.dart';

/// BioBalance colours. Light and dark share one set of meanings.
class Palette {
  const Palette._();

  static const emerald = Color(0xFF0B7A4B);
  static const teal = Color(0xFF0FA08A);
  static const lime = Color(0xFF9BE15D);
  static const leaf = Color(0xFF6ABE4E);
  static const ink = Color(0xFF0F1C16);
  static const amber = Color(0xFFB26A00);
  static const amberSoft = Color(0xFFFFF1D6);
  static const danger = Color(0xFFC0362C);
  static const dangerSoft = Color(0xFFFDE8E6);
  static const info = Color(0xFF1C6FB0);
  static const infoSoft = Color(0xFFE4F0FB);

  /// The brand gradient: primary buttons, the selected tab, hero cards.
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B7A4B), Color(0xFF0FA08A)],
  );
  static const brandDark = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2FBF7F), Color(0xFF29C7B0)],
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

  /// The brand gradient for this brightness, and the soft glow behind home screens.
  final LinearGradient gradient;
  final Color glow;

  static const light = StatusColors(
    success: Color(0xFF0B7A4B),
    successSoft: Color(0xFFE2F5EC),
    warning: Palette.amber,
    warningSoft: Palette.amberSoft,
    danger: Palette.danger,
    dangerSoft: Palette.dangerSoft,
    info: Palette.info,
    infoSoft: Palette.infoSoft,
    muted: Color(0xFF5C6B64),
    mutedSoft: Color(0xFFEDF2EF),
    card: Colors.white,
    hairline: Color(0xFFE3EAE6),
    shadow: Color(0x0D0F2A1E),
    gradient: Palette.brand,
    glow: Color(0xFFBDEBD5),
  );

  static const dark = StatusColors(
    success: Color(0xFF5FD69C),
    successSoft: Color(0xFF14321F),
    warning: Color(0xFFF2B65C),
    warningSoft: Color(0xFF3A2A0E),
    danger: Color(0xFFFF8F84),
    dangerSoft: Color(0xFF43191A),
    info: Color(0xFF8CC5F2),
    infoSoft: Color(0xFF11304A),
    muted: Color(0xFF9AA9A1),
    mutedSoft: Color(0xFF1C2622),
    card: Color(0xFF121B17),
    hairline: Color(0xFF223029),
    shadow: Color(0x40000000),
    gradient: Palette.brandDark,
    glow: Color(0xFF0E3D2A),
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
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

class AppTheme {
  const AppTheme._();

  static const radius = 20.0;
  static const _control = 16.0;

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: Palette.emerald,
      brightness: Brightness.light,
    ).copyWith(
      primary: Palette.emerald,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDDF4E8),
      onPrimaryContainer: const Color(0xFF053D25),
      secondary: Palette.teal,
      tertiary: Palette.lime,
      surface: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF2F6F4),
      surfaceContainer: const Color(0xFFEEF3F0),
      onSurface: Palette.ink,
      outlineVariant: const Color(0xFFE3EAE6),
      error: Palette.danger,
    ),
    StatusColors.light,
    scaffold: const Color(0xFFF5F8F6),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: Palette.emerald,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF5FD69C),
      onPrimary: const Color(0xFF00301B),
      primaryContainer: const Color(0xFF14321F),
      onPrimaryContainer: const Color(0xFFC7F2DB),
      secondary: const Color(0xFF29C7B0),
      tertiary: Palette.lime,
      surface: const Color(0xFF121B17),
      surfaceContainerLow: const Color(0xFF16201B),
      surfaceContainer: const Color(0xFF1A2520),
      onSurface: const Color(0xFFE7EFEA),
      outlineVariant: const Color(0xFF223029),
    ),
    StatusColors.dark,
    scaffold: const Color(0xFF09100D),
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
        labelSmall: t.labelSmall?.copyWith(letterSpacing: 0.3),
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
      // The main action wears the brand gradient.
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54)),
          shape: WidgetStatePropertyAll(control),
          textStyle: const WidgetStatePropertyAll(buttonText),
          elevation: const WidgetStatePropertyAll(0),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? status.muted
                : scheme.onPrimary,
          ),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: WidgetStatePropertyAll(
            scheme.onPrimary.withValues(alpha: 0.12),
          ),
          backgroundBuilder: (context, states, child) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_control),
              gradient: states.contains(WidgetState.disabled)
                  ? null
                  : status.gradient,
              color: states.contains(WidgetState.disabled)
                  ? status.mutedSoft
                  : null,
              boxShadow: states.contains(WidgetState.disabled)
                  ? null
                  : [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.22),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: child,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          shape: control,
          side: BorderSide(color: status.hairline, width: 1.2),
          backgroundColor: status.card,
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
        elevation: 6,
        highlightElevation: 8,
        extendedTextStyle: buttonText,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: status.card,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
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
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_control),
          borderSide: BorderSide(color: scheme.error),
        ),
        hintStyle: TextStyle(color: status.muted),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: const StadiumBorder(),
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
          borderSide: BorderSide(color: scheme.primary, width: 3),
          borderRadius: BorderRadius.circular(3),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: status.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: status.hairline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: status.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }
}
