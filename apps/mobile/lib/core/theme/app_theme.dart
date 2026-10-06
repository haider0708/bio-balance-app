import 'package:flutter/material.dart';

/// BioBalance colours. Light and dark share one set of meanings.
class Palette {
  const Palette._();

  static const emerald = Color(0xFF146C43);
  static const leaf = Color(0xFF6ABE4E);
  static const mint = Color(0xFFF1F8F4);
  static const ink = Color(0xFF17231C);
  static const line = Color(0xFFDCE5DF);
  static const amber = Color(0xFFB26A00);
  static const amberSoft = Color(0xFFFFF3DC);
  static const danger = Color(0xFFB3261E);
  static const dangerSoft = Color(0xFFFCE8E6);
  static const info = Color(0xFF1B6CA8);
  static const infoSoft = Color(0xFFE5F1FA);
}

/// Colours with a meaning (status, warnings) that the Material scheme does not carry.
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

  static const light = StatusColors(
    success: Palette.emerald,
    successSoft: Color(0xFFE3F3EA),
    warning: Palette.amber,
    warningSoft: Palette.amberSoft,
    danger: Palette.danger,
    dangerSoft: Palette.dangerSoft,
    info: Palette.info,
    infoSoft: Palette.infoSoft,
    muted: Color(0xFF5D6B63),
    mutedSoft: Color(0xFFEEF2EF),
  );

  static const dark = StatusColors(
    success: Color(0xFF7AD39B),
    successSoft: Color(0xFF1B3A29),
    warning: Color(0xFFF0B45A),
    warningSoft: Color(0xFF3F2E10),
    danger: Color(0xFFFFB4AB),
    dangerSoft: Color(0xFF4A1A16),
    info: Color(0xFF8FC7F0),
    infoSoft: Color(0xFF14324A),
    muted: Color(0xFFA8B5AD),
    mutedSoft: Color(0xFF26302A),
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

class AppTheme {
  const AppTheme._();

  static const _radius = 14.0;

  static ThemeData light() => _build(
    ColorScheme.fromSeed(
      seedColor: Palette.emerald,
      brightness: Brightness.light,
    ).copyWith(
      primary: Palette.emerald,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFE3F3EA),
      onPrimaryContainer: const Color(0xFF0B3D26),
      secondary: Palette.leaf,
      surface: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Palette.mint,
      surfaceContainer: Palette.mint,
      onSurface: Palette.ink,
      outlineVariant: Palette.line,
      error: Palette.danger,
    ),
    StatusColors.light,
    scaffold: const Color(0xFFF7FAF8),
  );

  static ThemeData dark() => _build(
    ColorScheme.fromSeed(
      seedColor: Palette.emerald,
      brightness: Brightness.dark,
    ).copyWith(
      primary: const Color(0xFF7AD39B),
      onPrimary: const Color(0xFF00391F),
      primaryContainer: const Color(0xFF1B3A29),
      onPrimaryContainer: const Color(0xFFCFF0DB),
      surface: const Color(0xFF121A15),
      surfaceContainerLow: const Color(0xFF18221C),
      surfaceContainer: const Color(0xFF1C2620),
      outlineVariant: const Color(0xFF2E3B33),
    ),
    StatusColors.dark,
    scaffold: const Color(0xFF0E1511),
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
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(_radius),
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            fontFamily: 'Inter',
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: shape,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            fontFamily: 'Inter',
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: shape,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFamily: 'Inter',
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radius),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
          color: scheme.onSurface,
        ),
        secondaryLabelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter',
          color: scheme.onPrimaryContainer,
        ),
        selectedColor: scheme.primaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        height: 68,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
            fontFamily: 'Inter',
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
      ),
    );
  }
}
