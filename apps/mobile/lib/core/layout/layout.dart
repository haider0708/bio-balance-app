/// Widths shared by every layout: phone, tablet and the web console.
library;

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
