import 'package:flutter/material.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const String _appName = 'eLeagueHub';
  static const String _supportEmail = 'support-esportlyic@kainuwa.africa';
  static const String _effectiveDate = '15 February 2026';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
      ),
      backgroundColor: cs.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: _LegalDoc(
                title: 'Terms of Service',
                subtitle: 'Effective date: $_effectiveDate',
                children: const [
                  _P(
                    'These Terms of Service (“Terms”) govern your access to and use of $_appName (the “App”, “we”, “us”, or “our”). '
                    'By downloading, accessing, or using the App, you agree to be bound by these Terms. If you do not agree, do not use the App.',
                  ),
                  _H('1) Eligibility'),
                  _P(
                    'You must be at least 13 years old (or older if required by the laws in your jurisdiction) to use the App. '
                    'If you are using the App on behalf of an organization, you represent that you have authority to bind that organization to these Terms.',
                  ),
                  _H('2) Accounts and authentication'),
                  _P(
                    'Some features require an account. You agree to provide accurate information and to keep your account information up to date. '
                    'You are responsible for safeguarding your account and for any activity that occurs under your account.',
                  ),
                  _P(
                    'We may suspend or terminate accounts that we reasonably believe are compromised, used for fraud, or violate these Terms.',
                  ),
                  _H('3) User responsibilities'),
                  _P(
                    'You agree to use the App responsibly and in compliance with all applicable laws and regulations. You agree that you will not:',
                  ),
                  _B('Use the App for unlawful, fraudulent, or harmful activity.'),
                  _B('Attempt to gain unauthorized access to accounts, systems, or networks.'),
                  _B('Interfere with, disrupt, or degrade the performance or security of the App.'),
                  _B('Upload or share content that infringes intellectual property rights or violates privacy rights.'),
                  _B('Transmit malware, spyware, or other harmful code.'),
                  _B('Abuse, harass, or threaten other users, or promote hate or violence.'),
                  _H('4) Acceptable use and content'),
                  _P(
                    'You are responsible for any content you submit through the App (such as profile names or images). You represent and warrant that you have the necessary rights to submit such content and that it does not violate any law or third-party rights.',
                  ),
                  _P(
                    'We reserve the right to remove or restrict access to content that violates these Terms, applicable law, or platform policies, or that we believe may harm users or the service.',
                  ),
                  _H('5) Leagues and marketplace usage'),
                  _P(
                    'The App may allow you to create, manage, or participate in leagues. You are responsible for how you organize leagues and for ensuring that your league operations comply with applicable laws, rules, and platform policies.',
                  ),
                  _P(
                    'The App may also display marketplace content and outbound links to third-party stores or partners. We may update, remove, or change marketplace content at any time.',
                  ),
                  _H('6) Affiliate products disclaimer'),
                  _P(
                    'Some marketplace links may be affiliate links. This means we may earn a commission if you click a link and make a purchase from a third-party store. '
                    'Your purchase is completed on third-party platforms, and those platforms are solely responsible for order fulfillment, payments, shipping, refunds, warranties, and customer service.',
                  ),
                  _P(
                    'We do not manufacture, sell, or ship third-party products, and we do not guarantee product availability, pricing, or the accuracy of third-party listings.',
                  ),
                  _H('7) Third-party services and links'),
                  _P(
                    'The App may integrate with or rely on third-party services (such as Firebase/Google for authentication and backend services, Cloudinary for image storage, and partner sites for outbound links). '
                    'Your use of third-party services is governed by their own terms and policies. We are not responsible for third-party services.',
                  ),
                  _H('8) Intellectual property'),
                  _P(
                    'The App, including its design, text, graphics, logos, and software, is owned by us or our licensors and is protected by intellectual property laws. '
                    'We grant you a limited, non-exclusive, non-transferable, revocable license to use the App for your personal or internal business purposes in accordance with these Terms.',
                  ),
                  _P(
                    'You may not copy, modify, distribute, sell, lease, reverse engineer, or attempt to extract the source code of the App except to the extent such restrictions are prohibited by law.',
                  ),
                  _H('9) Suspension and termination'),
                  _P(
                    'We may suspend or terminate your access to the App at any time if we reasonably believe you have violated these Terms, created risk for other users, or exposed us to legal liability.',
                  ),
                  _P(
                    'You may stop using the App at any time. If you wish to request deletion of your account data, contact us at $_supportEmail.',
                  ),
                  _H('10) Disclaimer of warranties'),
                  _P(
                    'THE APP IS PROVIDED “AS IS” AND “AS AVAILABLE”. TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE DISCLAIM ALL WARRANTIES, EXPRESS OR IMPLIED, INCLUDING IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, AND NON-INFRINGEMENT.',
                  ),
                  _H('11) Limitation of liability'),
                  _P(
                    'TO THE MAXIMUM EXTENT PERMITTED BY LAW, IN NO EVENT WILL WE BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF PROFITS, REVENUE, DATA, OR GOODWILL, ARISING OUT OF OR RELATED TO YOUR USE OF (OR INABILITY TO USE) THE APP, EVEN IF WE HAVE BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.',
                  ),
                  _P(
                    'TO THE MAXIMUM EXTENT PERMITTED BY LAW, OUR TOTAL LIABILITY FOR ALL CLAIMS ARISING OUT OF OR RELATED TO THESE TERMS OR THE APP WILL NOT EXCEED THE AMOUNT YOU PAID (IF ANY) TO USE THE APP IN THE 12 MONTHS PRECEDING THE EVENT GIVING RISE TO THE CLAIM.',
                  ),
                  _H('12) Indemnification'),
                  _P(
                    'You agree to indemnify and hold us harmless from any claims, liabilities, damages, losses, and expenses (including reasonable legal fees) arising out of or related to: '
                    '(a) your use of the App, (b) your content, or (c) your violation of these Terms or applicable law.',
                  ),
                  _H('13) Changes to the App and Terms'),
                  _P(
                    'We may modify or discontinue any part of the App at any time. We may also update these Terms from time to time. '
                    'We will post the updated Terms in the App and update the effective date. Your continued use of the App after changes become effective constitutes acceptance of the updated Terms.',
                  ),
                  _H('14) Governing law'),
                  _P(
                    'These Terms are governed by the laws applicable in the jurisdiction where we operate, without regard to conflict of laws principles, unless otherwise required by applicable law.',
                  ),
                  _H('15) Contact'),
                  _P(
                    'If you have questions about these Terms or the App, contact us at: $_supportEmail',
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
