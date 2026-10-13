import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../api/json.dart';
import '../auth/session.dart';
import '../brand/leaf_mark.dart';
import '../theme/app_theme.dart';

/// This build's number (the part after "+" in the version); 0 when it cannot be read.
final appBuildProvider = FutureProvider<int>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return int.tryParse(info.buildNumber) ?? 0;
});

/// Set when the server no longer supports this build: where to update it (null when the store
/// page is not known yet). The web console is always current, and a phone that cannot ask the
/// server (offline, server down) is never blocked.
final updateRequiredProvider = FutureProvider<UpdateRequired?>((ref) async {
  if (kIsWeb) return null;
  try {
    final build = await ref.watch(appBuildProvider.future);
    final config = await ref.read(apiClientProvider).get('/v1/app-config');
    if (config is! Json) return null;
    if (build == 0 || build >= config.integer('minimumBuild')) return null;
    final stores = config.objOrNull('stores') ?? const <String, dynamic>{};
    final link = defaultTargetPlatform == TargetPlatform.iOS
        ? stores['ios']
        : stores['android'];
    return UpdateRequired(link is String && link.isNotEmpty ? link : null);
  } on Object {
    return null;
  }
});

class UpdateRequired {
  const UpdateRequired(this.storeUrl);

  final String? storeUrl;
}

/// Shows [child], or the "Update required" screen when this build is no longer supported. Checks
/// again whenever the app comes back to the screen.
class UpdateGate extends ConsumerStatefulWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(updateRequiredProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateRequiredProvider).value;
    return update == null ? widget.child : UpdateRequiredScreen(update);
  }
}

class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen(this.update, {super.key});

  final UpdateRequired update;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final url = update.storeUrl;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const SizedBox(
                    width: 96,
                    height: 96 * LeafMark.aspect,
                    child: CustomPaint(painter: LeafMarkPainter()),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    t.updateRequiredTitle,
                    textAlign: TextAlign.center,
                    style: context.text.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    url == null
                        ? t.updateRequiredFromStore
                        : t.updateRequiredBody,
                    textAlign: TextAlign.center,
                    style: context.text.bodyLarge?.copyWith(
                      color: context.status.muted,
                    ),
                  ),
                  if (url != null) ...[
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Text(t.updateNow),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
