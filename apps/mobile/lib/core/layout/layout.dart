/// Widths shared by every layout: phone, tablet and the web console.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Width from which a screen is a tablet or a desktop: side navigation instead of a bottom bar.
const wideBreakpoint = 720.0;

/// The widest a page's content grows on a large screen.
const contentMaxWidth = 1120.0;

/// Forms and settings read better narrow: inputs stretched over a large screen are hard to follow.
const formMaxWidth = 680.0;

/// Pages that are a form (create, edit, count, ship, receive...), not a list or a dashboard.
bool isFormPath(String path) =>
    path == '/settings' ||
    RegExp(r'/(new|edit|declare|adjust|ship|receive|restock|correct)$')
        .hasMatch(path);

/// The space a bottom sheet keeps under its content: the keyboard when it is open, otherwise the
/// phone's home bar (a sheet's own safe area only covers its top), so the last button is never
/// under the home gesture.
double sheetBottomInset(BuildContext context) => math.max(
  MediaQuery.viewInsetsOf(context).bottom,
  MediaQuery.viewPaddingOf(context).bottom,
);
