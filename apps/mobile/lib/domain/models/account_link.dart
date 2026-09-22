class AccountLink {
  final String mode, token;
  const AccountLink(this.mode, this.token);
  static AccountLink? parse(Uri uri, {String httpsHost = ''}) {
    if (uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) return null;
    final action =
        uri.scheme == 'https' &&
            httpsHost.isNotEmpty &&
            uri.host == httpsHost &&
            uri.port == 443
        ? uri.path.replaceFirst('/', '')
        : '';
    if (!['activate', 'recover'].contains(action)) return null;
    final tokens = uri.queryParametersAll['token'];
    if (tokens == null ||
        tokens.length != 1 ||
        !RegExp(r'^[A-Za-z0-9_-]{32,200}$').hasMatch(tokens.single)) {
      return null;
    }
    return AccountLink(
      action == 'activate' ? 'activate' : 'reset',
      tokens.single,
    );
  }
}
