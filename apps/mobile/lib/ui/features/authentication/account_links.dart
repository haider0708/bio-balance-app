import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/account_link.dart';
import 'login_screen.dart';
import 'session_view_model.dart';

class AccountLinks extends StatefulWidget {
  final GlobalKey<NavigatorState> navigator;
  final Widget child;
  const AccountLinks({super.key, required this.navigator, required this.child});
  @override
  State<AccountLinks> createState() => _AccountLinksState();
}

class _AccountLinksState extends State<AccountLinks> {
  StreamSubscription<Uri>? subscription;
  SessionViewModel? session;
  AccountLink? pending;
  final seen = <String>{};
  bool handling = false;
  @override
  void initState() {
    super.initState();
    final links = AppLinks();
    subscription = links.uriLinkStream.listen(receive, onError: (Object _) {});
    unawaited(
      links
          .getInitialLink()
          .then((uri) {
            if (uri != null) receive(uri);
          })
          .catchError((Object _) {}),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = context.read<SessionViewModel>();
    if (current != session) {
      session?.removeListener(schedule);
      session = current;
      session!.addListener(schedule);
    }
    schedule();
  }

  void receive(Uri uri) {
    final link = AccountLink.parse(
      uri,
      httpsHost: const String.fromEnvironment('AUTH_LINK_HOST'),
    );
    if (!mounted || link == null || !seen.add('${link.mode}:${link.token}')) {
      return;
    }
    if (seen.length > 100) seen.remove(seen.first);
    pending = link;
    schedule();
  }

  void schedule() {
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(open());
      });
    }
  }

  Future<void> open() async {
    if (handling ||
        pending == null ||
        session == null ||
        session!.state.restoring) {
      return;
    }
    final navigator = widget.navigator.currentState;
    if (navigator == null) return;
    handling = true;
    final link = pending!;
    pending = null;
    try {
      final email = session!.state.user?.email;
      if (email != null) {
        final confirmed = await showDialog<bool>(
          context: navigator.context,
          builder: (context) => AlertDialog(
            title: const Text('Ouvrir ce lien de compte ?'),
            content: Text(
              'Vous êtes connecté avec $email. Déconnectez-vous pour continuer. Vos brouillons et opérations sont conservés.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Se déconnecter et continuer'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
        await session!.logout();
      }
      if (!mounted) return;
      navigator.popUntil((route) => route.isFirst);
      await navigator.push(
        MaterialPageRoute(
          builder: (_) =>
              AccountActionScreen(mode: link.mode, initialToken: link.token),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(SessionViewModel.message(e))));
      }
    } finally {
      handling = false;
      if (pending != null) schedule();
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    session?.removeListener(schedule);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
