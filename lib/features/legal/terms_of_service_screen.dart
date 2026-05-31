import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const String _appName = 'eSportlyic';
  static const String _supportEmail = 'NASSARACORETECHVENTURES@GMAIL.COM';
  static const String _effectiveDate = '15 February 2026';

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Terms of Service'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: kToolbarHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Glass(
                  borderRadius: 22,
                  padding: const EdgeInsets.all(18),
                  child: _LegalDoc(
                    title: 'Terms of Service',
                    subtitle: '$_appName · Effective date: $_effectiveDate',
                    children: [
                      // ── 1. Acceptance of Terms ─────────────────────────
                      const _H('1. Acceptance of Terms'),
                      const _P(
                        'By downloading, accessing, or using $_appName ("the App"), '
                        'you agree to be bound by these Terms of Service. '
                        'If you do not agree, you must not use the App.',
                      ),

                      // ── 2. Eligibility ─────────────────────────────────
                      const _H('2. Eligibility'),
                      const _P(
                        'You must be at least 13 years old (or the minimum legal age '
                        'in your country) to use the App. By using the App, you '
                        'confirm that you meet this requirement.',
                      ),
                      const _P(
                        'If you are using the App on behalf of an organization, you '
                        'confirm that you have authority to bind that organization to '
                        'these Terms.',
                      ),

                      // ── 3. Account Registration ────────────────────────
                      const _H('3. Account Registration and Security'),
                      const _P(
                        'Some features require an account created through Firebase '
                        'Authentication or supported login providers.',
                      ),
                      const _P('You agree to:'),
                      const _B('Provide accurate and complete information.'),
                      const _B('Keep your login credentials secure.'),
                      const _B('Accept responsibility for all activity under your account.'),
                      const _P(
                        'We reserve the right to suspend or terminate accounts '
                        'suspected of abuse, fraud, or violation of these Terms.',
                      ),

                      // ── 4. Use of the App ──────────────────────────────
                      const _H('4. Use of the App'),
                      const _P(
                        'You agree to use the App only for lawful purposes and in a '
                        'way that does not harm, disrupt, or interfere with other '
                        'users or the App.',
                      ),
                      const _P('You must not:'),
                      const _B('Use the App for illegal, harmful, or fraudulent activity.'),
                      const _B('Attempt unauthorized access to systems or accounts.'),
                      const _B('Interfere with App performance or security.'),
                      const _B('Upload malicious code or content.'),
                      const _B('Harass, abuse, or threaten other users.'),
                      const _B('Violate intellectual property or privacy rights.'),

                      // ── 5. Camera / Microphone / Screen Recording ──────
                      const _H('5. Camera, Microphone, and Screen Recording Use'),
                      const _P('The App may request access to:'),
                      const _B('Camera — for profile images, content creation, or streaming features.'),
                      const _B('Microphone — for voice communication, live interaction, or recording features.'),
                      const _B('Screen recording (Media Projection) — for live streaming, screen sharing, or gameplay capture.'),
                      const _P('These features:'),
                      const _B('Are only activated when you explicitly start them.'),
                      const _B('Do not run in the background without your action.'),
                      const _B('Can be disabled at any time through device settings or in-app controls.'),

                      // ── 6. Overlay Permission ──────────────────────────
                      const _H('6. Overlay (Floating Window) Features'),
                      const _P(
                        'The App may use overlay permissions to display floating '
                        'elements such as:',
                      ),
                      const _B('Chat heads.'),
                      const _B('Voice controls.'),
                      const _B('Live session tools.'),
                      const _P('These overlays:'),
                      const _B('Appear only during active use of supported features.'),
                      const _B('Do not collect personal data by themselves.'),
                      const _B('Can be disabled by the user at any time.'),

                      // ── 7. User Content ────────────────────────────────
                      const _H('7. User Content'),
                      const _P(
                        'You are responsible for any content you upload, create, or '
                        'share through the App, including:',
                      ),
                      const _B('Profile information.'),
                      const _B('Images.'),
                      const _B('League data or content.'),
                      const _P('You confirm that:'),
                      const _B('You own or have permission to use the content you upload.'),
                      const _B('Your content does not violate any laws or third-party rights.'),
                      const _P(
                        'We may remove content that violates these Terms or applicable '
                        'policies.',
                      ),

                      // ── 8. Leagues and Community Features ─────────────
                      const _H('8. Leagues and Community Features'),
                      const _P(
                        'The App allows users to create and manage leagues and '
                        'participate in community activities.',
                      ),
                      const _P(
                        'You are responsible for how you organize and manage your '
                        'leagues, including compliance with applicable laws and '
                        'community standards.',
                      ),
                      const _P(
                        'We are not responsible for disputes between users or league '
                        'participants.',
                      ),

                      // ── 9. Marketplace and Affiliate Links ─────────────
                      const _H('9. Marketplace and Affiliate Links'),
                      const _P(
                        'The App may display marketplace content and external links.',
                      ),
                      const _P(
                        'Some links may be affiliate links, meaning we may earn a '
                        'commission if you make a purchase.',
                      ),
                      const _SubH('Important:'),
                      const _B('Purchases are made on third-party websites.'),
                      const _B('We are not responsible for pricing, delivery, refunds, or product quality.'),
                      const _B('Third-party services are governed by their own terms.'),

                      // ── 10. Third-Party Services ───────────────────────
                      const _H('10. Third-Party Services'),
                      const _P(
                        'The App relies on third-party services including:',
                      ),
                      const _B('Google Firebase — authentication, database, crash reporting.'),
                      const _B('Cloudinary — image storage and delivery.'),
                      const _B('External websites or partners linked in marketplace content.'),
                      const _P(
                        'We are not responsible for third-party services or their '
                        'policies.',
                      ),

                      // ── 11. Intellectual Property ──────────────────────
                      const _H('11. Intellectual Property'),
                      const _P(
                        'All App content, design, features, and software are owned by '
                        '$_appName or its licensors.',
                      ),
                      const _P(
                        'You are granted a limited, non-exclusive, non-transferable '
                        'license to use the App for personal or internal purposes.',
                      ),
                      const _P('You may not:'),
                      const _B('Copy or modify the App.'),
                      const _B('Reverse engineer or extract source code.'),
                      const _B('Distribute or resell the App.'),

                      // ── 12. Termination ────────────────────────────────
                      const _H('12. Termination'),
                      const _P(
                        'We may suspend or terminate your access to the App if:',
                      ),
                      const _B('You violate these Terms.'),
                      const _B('You misuse the App.'),
                      const _B('Your actions create risk for users or the platform.'),
                      const _P('You may stop using the App at any time.'),

                      // ── 13. Disclaimer of Warranties ──────────────────
                      const _H('13. Disclaimer of Warranties'),
                      const _P(
                        'The App is provided "as is" and "as available" without '
                        'warranties of any kind.',
                      ),
                      const _P('We do not guarantee:'),
                      const _B('That the App will be error-free.'),
                      const _B('That the App will be uninterrupted.'),
                      const _B('That all features will function at all times.'),

                      // ── 14. Limitation of Liability ────────────────────
                      const _H('14. Limitation of Liability'),
                      const _P(
                        'To the maximum extent permitted by law, we are not liable for:',
                      ),
                      const _B('Indirect or incidental damages.'),
                      const _B('Loss of data, revenue, or profits.'),
                      const _B('App downtime or failure.'),
                      const _P(
                        'Our total liability will not exceed the amount you paid '
                        '(if any) to use the App in the last 12 months.',
                      ),

                      // ── 15. Indemnification ────────────────────────────
                      const _H('15. Indemnification'),
                      const _P(
                        'You agree to indemnify and hold harmless $_appName from any '
                        'claims, damages, or expenses arising from:',
                      ),
                      const _B('Your use of the App.'),
                      const _B('Your content.'),
                      const _B('Your violation of these Terms.'),

                      // ── 16. Data Protection and Privacy ───────────────
                      const _H('16. Data Protection and Privacy'),
                      const _P(
                        'Your use of the App is also governed by our Privacy Policy, '
                        'which explains how we collect and process data including:',
                      ),
                      const _B('Authentication data.'),
                      const _B('Device information.'),
                      const _B('Camera, microphone, and screen recording usage.'),
                      const _B('Uploaded images and content.'),

                      // ── 17. Changes to Terms ───────────────────────────
                      const _H('17. Changes to Terms'),
                      const _P(
                        'We may update these Terms at any time. Updates will be posted '
                        'within the App with a revised effective date.',
                      ),
                      const _P(
                        'Continued use of the App means you accept the updated Terms.',
                      ),

                      // ── 18. Governing Law ──────────────────────────────
                      const _H('18. Governing Law'),
                      const _P(
                        'These Terms are governed by the applicable laws of the '
                        'jurisdiction in which the App operates, unless otherwise '
                        'required by local law.',
                      ),

                      // ── 19. Contact Information ────────────────────────
                      const _H('19. Contact Information'),
                      const _P(
                        'For questions about these Terms, contact us:',
                      ),
                      _EmailLink(email: _supportEmail),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal layout widgets
// ─────────────────────────────────────────────────────────────────────────────

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
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: t.bodySmall?.copyWith(
            color: cs.onSurface.withOpacity(0.65),
            fontWeight: FontWeight.w600,
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Divider(),
        ),
        ...children,
      ],
    );
  }
}

/// Large section heading  e.g. "1. Acceptance of Terms"
class _H extends StatelessWidget {
  const _H(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          color: cs.primary,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// Sub-section heading  e.g. "Important:"
class _SubH extends StatelessWidget {
  const _SubH(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        text,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: cs.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// Body paragraph
class _P extends StatelessWidget {
  const _P(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: cs.onSurface.withOpacity(0.88),
          height: 1.55,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}

/// Bullet point
class _B extends StatelessWidget {
  const _B(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
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
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withOpacity(0.88),
                height: 1.55,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable e-mail link
class _EmailLink extends StatelessWidget {
  const _EmailLink({required this.email});

  final String email;

  Future<void> _launch() async {
    final uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: _launch,
        child: Row(
          children: [
            Icon(Icons.email_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              email,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: cs.primary,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
