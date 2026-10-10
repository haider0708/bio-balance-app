import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config.dart';
import '../../l10n/app_localizations.dart';

/// The public pages the app stores require, served by the API in French and English.
enum LegalPage {
  privacy('privacy'),
  terms('terms'),
  deletion('account-deletion');

  const LegalPage(this.path);

  final String path;
}

Uri legalUri(LegalPage page, String locale) =>
    Uri.parse('${AppConfig.publicSiteUrl}/${page.path}')
        .replace(queryParameters: {'lang': locale == 'en' ? 'en' : 'fr'});

/// Opens the page in a browser view over the app.
Future<void> openLegal(BuildContext context, LegalPage page) async {
  final locale = AppLocalizations.of(context).localeName;
  await launchUrl(legalUri(page, locale), mode: LaunchMode.inAppBrowserView);
}

/// "Privacy policy · Terms of use", small, under a sign-in form.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final style = TextButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: Theme.of(context).textTheme.bodySmall,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          style: style,
          onPressed: () => openLegal(context, LegalPage.privacy),
          child: Text(t.privacyPolicy),
        ),
        Text('·', style: Theme.of(context).textTheme.bodySmall),
        TextButton(
          style: style,
          onPressed: () => openLegal(context, LegalPage.terms),
          child: Text(t.termsOfUse),
        ),
      ],
    );
  }
}
