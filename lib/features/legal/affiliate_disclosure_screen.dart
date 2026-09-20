import 'package:flutter/material.dart';

import '../../core/locale/app_localizations.dart';

class AffiliateDisclosureScreen extends StatelessWidget {
  const AffiliateDisclosureScreen({super.key});

  static const String _appName = 'eSportlyic';
  static const String _supportEmail = 'NASSARACORETECHVENTURES@GMAIL.COM';
  static const String _effectiveDate = '15 February 2026';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('affiliate_appbar_title')),
      ),
      backgroundColor: cs.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: _LegalDoc(
                title: l10n.tr('affiliate_appbar_title'),
                subtitle: '${l10n.tr('affiliate_subtitle_prefix')}$_effectiveDate',
                children: [
                  _P(
                    '$_appName${l10n.tr('affiliate_intro_suffix')}',
                  ),
                  _H(l10n.tr('affiliate_h_what_this_means')),
                  _B(l10n.tr('affiliate_b_no_extra_cost')),
                  _B(l10n.tr('affiliate_b_prices_availability')),
                  _B(l10n.tr('affiliate_b_transactions')),
                  _H(l10n.tr('affiliate_h_partner_responsibility')),
                  _P(
                    '${l10n.tr('affiliate_partner_responsibility_prefix')}$_appName${l10n.tr('affiliate_partner_responsibility_suffix')}',
                  ),
                  _H(l10n.tr('affiliate_h_editorial_independence')),
                  _P(l10n.tr('affiliate_editorial_independence_body')),
                  _H(l10n.tr('affiliate_h_questions')),
                  _P(
                    '${l10n.tr('affiliate_questions_prefix')}$_supportEmail',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalDoc extends StatelessWidget {
  const _LegalDoc({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: t.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onBackground,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: t.bodySmall?.copyWith(
            color: cs.onBackground.withOpacity(0.70),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ...children,
        const SizedBox(height: 8),
      ],
    );
  }
}

class _H extends StatelessWidget {
  const _H(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: t.titleMedium?.copyWith(
          color: cs.onBackground,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _P extends StatelessWidget {
  const _P(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: t.bodyMedium?.copyWith(
          color: cs.onBackground.withOpacity(0.88),
          height: 1.35,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _B extends StatelessWidget {
  const _B(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.textTheme;
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: t.bodyMedium?.copyWith(
                color: cs.onBackground.withOpacity(0.88),
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
