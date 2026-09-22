import 'package:flutter/material.dart';

const brandGreen = Color(0xFF6ABE4E);
const darkGreen = Color(0xFF286B34);
const ink = Color(0xFF1C1E22);
const muted = Color(0xFF606164);
ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Inter',
  brightness: Brightness.light,
  colorScheme: ColorScheme.fromSeed(
    seedColor: darkGreen,
    primary: darkGreen,
    surface: Colors.white,
    error: const Color(0xFFAF342C),
  ),
  scaffoldBackgroundColor: const Color(0xFFF6F8F4),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 16, color: ink, height: 1.45),
    bodyMedium: TextStyle(fontSize: 16, color: ink, height: 1.4),
    bodySmall: TextStyle(fontSize: 14, color: muted, height: 1.4),
    titleLarge: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    foregroundColor: ink,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDDE3D9)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDDE3D9)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(48, 52),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(48, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE5E9E1)),
    ),
  ),
  navigationBarTheme: const NavigationBarThemeData(
    labelPadding: EdgeInsets.zero,
    labelTextStyle: WidgetStatePropertyAll(
      TextStyle(fontSize: 14, letterSpacing: -0.3, fontWeight: FontWeight.w500),
    ),
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
        padding: const EdgeInsets.all(20),
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
    padding: const EdgeInsets.only(bottom: 20, top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
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
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, size: 48, color: darkGreen),
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
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFBECE9) : const Color(0xFFEBF5E7),
      borderRadius: BorderRadius.circular(12),
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

class StatusChip extends StatelessWidget {
  final String text;
  final IconData icon;
  const StatusChip(
    this.text, {
    super.key,
    this.icon = Icons.check_circle_outline,
  });
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 5,
    children: [
      Icon(icon, size: 18, color: darkGreen),
      Text(text, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
