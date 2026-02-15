import 'package:flutter/material.dart';

class AffiliateDisclosureScreen extends StatelessWidget {
  const AffiliateDisclosureScreen({super.key});

  static const String _appName = 'eLeagueHub';
  static const String _supportEmail = 'support-esportlyic@kainuwa.africa';
  static const String _effectiveDate = '15 February 2026';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Affiliate Disclosure'),
      ),
      backgroundColor: cs.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: _LegalDoc(
                title: 'Affiliate Disclosure',
                subtitle: 'Effective date: $_effectiveDate',
                children: const [
                  _P(
                    '$_appName participates in affiliate marketing programs. This means some links shown in the App may be “affiliate links.” '
                    'If you click an affiliate link and make a purchase from a third-party store, we may earn a commission or referral fee.',
                  ),
                  _H('What this means for you'),
                  _B(
                    'You pay no extra cost. Affiliate commissions are paid by the third-party store, not by you.',
                  ),
                  _B(
                    'Prices and availability are determined by external partner stores and may change at any time.',
                  ),
                  _B(
                    'Transactions happen on external partner sites/apps. The partner store processes payments, shipping, refunds, warranties, and customer service.',
                  ),
                  _H('Partner store responsibility'),
                  _P(
                    'Because purchases are completed on third-party platforms, $_appName is not responsible for issues related to orders, payments, shipping, returns, refunds, or product quality. '
                    'Any dispute or request regarding a purchase must be addressed directly with the partner store or merchant.',
                  ),
                  _H('Editorial independence'),
                  _P(
                    'Where marketplace content is shown, we aim to present products and links that may be useful to users. '
                    'Any affiliate relationship does not guarantee that all products are reviewed, endorsed, or recommended by us, and you should always conduct your own research before purchasing.',
                  ),
                  _H('Questions'),
                  _P(
                    'If you have questions about this Affiliate Disclosure, contact us at: $_supportEmail',
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
