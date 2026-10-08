import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// On a wide browser window the app keeps the width it was designed for, centred on a calm backdrop.
/// On a phone, or a narrow window, it fills the screen as usual.
class WebFrame extends StatelessWidget {
  const WebFrame({required this.child, super.key});

  static const maxWidth = 760.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || MediaQuery.sizeOf(context).width <= maxWidth + 40) {
      return child;
    }
    final s = context.status;
    return ColoredBox(
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.black
          : s.hairline.withValues(alpha: 0.35),
      child: Center(
        child: Container(
          width: maxWidth,
          decoration: BoxDecoration(
            border: Border.symmetric(vertical: BorderSide(color: s.hairline)),
          ),
          clipBehavior: Clip.antiAlias,
          child: MediaQuery.removePadding(context: context, child: child),
        ),
      ),
    );
  }
}
