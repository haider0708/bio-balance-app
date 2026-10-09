import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/components.dart';
import '../../l10n/app_localizations.dart';
import 'auth_widgets.dart';
import 'login_screen.dart';

/// Web-only administrator sign-in: full-bleed console layout, not the phone auth screen.
class AdminLoginScreen extends StatelessWidget {
  const AdminLoginScreen({this.email, super.key});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = _Card(email: email);

    return Scaffold(
      backgroundColor: context.theme.scaffoldBackgroundColor,
      body: wide
          ? Row(
              children: [
                const Expanded(flex: 5, child: _BrandPanel()),
                Expanded(
                  flex: 6,
                  child: ColoredBox(
                    color: context.status.card,
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 40,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: form,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : SafeArea(
              child: Column(
                children: [
                  const SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: _BrandPanel(compact: true),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: form,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    const onDark = Colors.white;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1220), Color(0xFF0C6B45), Color(0xFF0A3D32)],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            top: -60,
            child: _Ring(size: 220, color: onDark.withValues(alpha: 0.06)),
          ),
          Positioned(
            left: -50,
            bottom: -70,
            child: _Ring(size: 260, color: onDark.withValues(alpha: 0.05)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 24 : 48,
              compact ? 28 : 56,
              compact ? 24 : 48,
              compact ? 24 : 48,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: onDark.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: onDark.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Text(
                        'B',
                        style: TextStyle(
                          color: onDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      t.appName,
                      style: const TextStyle(
                        color: onDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
                if (!compact) ...[
                  const Spacer(),
                  Text(
                    t.adminConsoleTitle,
                    style: const TextStyle(
                      color: onDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 36,
                      height: 1.15,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    t.adminConsoleTagline,
                    style: TextStyle(
                      color: onDark.withValues(alpha: 0.78),
                      fontSize: 16,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'v${AppConfig.version}',
                    style: TextStyle(
                      color: onDark.withValues(alpha: 0.45),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      t.adminConsoleTitle,
                      style: const TextStyle(
                        color: onDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 28),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t.adminSignInTitle,
                style: context.text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const LanguageToggle(),
          ],
        ),
        const Gap(8),
        Text(
          t.adminSignInSubtitle,
          style: context.text.bodyMedium?.copyWith(color: context.status.muted),
        ),
        const Gap(28),
        SignInForm(email: email, icons: true),
      ],
    );
  }
}
