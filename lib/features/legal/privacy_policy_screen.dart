import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _appName = 'eSportlyic';
  static const String _supportEmail = 'NASSARACORETECHVENTURES@GMAIL.COM';
  static const String _effectiveDate = '15 February 2026';

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        automaticallyImplyLeading: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Glass(
                borderRadius: 22,
                padding: const EdgeInsets.all(18),
                child: _LegalDoc(
                  title: 'Privacy Policy',
                  subtitle: '$_appName · Effective date: $_effectiveDate',
                  children: [
                    // ── 1. Introduction ──────────────────────────────────
                    const _H('1. Introduction'),
                    _P(
                      'This Privacy Policy explains how $_appName collects, uses, stores, and protects your '
                      'information when you use our application.',
                    ),
                    const _P(
                      'By using the App, you agree to the practices described in '
                      'this Privacy Policy. If you do not agree, please do not use '
                      'the App.',
                    ),

                    // ── 2. Information We Collect ────────────────────────
                    const _H('2. Information We Collect'),
                    const _P('We collect the following types of information:'),

                    const _SubH('2.1 Information you provide directly'),
                    const _B(
                        'Account information such as email address (via Google/Firebase Authentication or other login methods).'),
                    const _B(
                        'Profile details such as team name, username, and profile photo.'),
                    const _B(
                        'Content you upload within the App (such as images or league-related data).'),
                    const _B(
                        'Support messages or communications you send to us.'),

                    const _SubH('2.2 Information collected automatically'),
                    const _P(
                        'When you use the App, we may automatically collect:'),
                    const _B(
                        'Device information (model, operating system version).'),
                    const _B('App version and usage data.'),
                    const _B(
                        'Crash logs and diagnostic data (for performance and bug fixing).'),
                    const _B('IP address and general network information.'),

                    const _SubH('2.3 Information from third-party services'),
                    const _P(
                      'If you sign in using third-party services (such as Google), '
                      'we may receive:',
                    ),
                    const _B('Unique user ID.'),
                    const _B('Email address.'),
                    const _B('Display name.'),
                    const _B('Profile photo (if available).'),
                    const _P(
                      'This data is provided in accordance with the third party\'s '
                      'privacy settings and policies.',
                    ),

                    // ── 3. Camera / Microphone / Screen Recording ────────
                    const _H('3. Camera, Microphone, and Screen Recording'),
                    const _P(
                      'The App may request access to sensitive device features only '
                      'when you explicitly use related features:',
                    ),
                    const _B(
                        'Camera access: used for profile images, streaming, or content creation.'),
                    const _B(
                        'Microphone access: used for voice chat, live communication, or recording features.'),
                    const _B(
                        'Screen recording (Media Projection): used only when you explicitly start screen sharing or live streaming sessions.'),
                    const _P(
                      'We do not access your camera, microphone, or screen in the '
                      'background without your active permission and interaction. '
                      'You can disable these permissions at any time in your device '
                      'settings.',
                    ),

                    // ── 4. Overlay Permission ────────────────────────────
                    const _H('4. Overlay (Floating Window) Permission'),
                    const _P(
                      'The App may display floating UI elements (such as chat heads, '
                      'voice controls, or live session controls) using overlay '
                      'permissions. These overlays:',
                    ),
                    const _B(
                        'Only appear during active features (e.g., live sessions or voice tools).'),
                    const _B('Do not collect personal data by themselves.'),
                    const _B(
                        'Can be disabled by the user through settings or system permissions.'),

                    // ── 5. How We Use Your Information ───────────────────
                    const _H('5. How We Use Your Information'),
                    const _P('We use collected information to:'),
                    const _B('Provide and operate the App.'),
                    const _B('Enable user accounts and authentication.'),
                    const _B('Support league and profile features.'),
                    const _B(
                        'Enable live interaction features (voice, streaming, etc.).'),
                    const _B('Improve performance and fix bugs.'),
                    const _B('Provide customer support.'),
                    const _B('Ensure security and prevent fraud or abuse.'),

                    // ── 6. Data Storage and Services ────────────────────
                    const _H('6. Data Storage and Services'),
                    const _P(
                      'We use trusted third-party services to operate the App, '
                      'including:',
                    ),
                    const _B(
                        'Google Firebase — Authentication, database, crash reporting.'),
                    const _B('Cloudinary — image storage and delivery.'),
                    const _P(
                      'These providers may process your data according to their own '
                      'privacy policies.',
                    ),

                    // ── 7. Sharing of Information ────────────────────────
                    const _H('7. Sharing of Information'),
                    const _P('We do not sell your personal data.'),
                    const _P(
                        'We may share information only in the following cases:'),
                    const _B(
                        'With service providers (Firebase, Cloudinary) to operate the App.'),
                    const _B('When required by law or legal process.'),
                    const _B(
                        'To protect user safety, security, or prevent abuse.'),
                    const _B(
                        'In case of business transfer (merger or acquisition).'),

                    // ── 8. Data Retention ────────────────────────────────
                    const _H('8. Data Retention'),
                    const _P(
                      'We keep your information only as long as necessary to:',
                    ),
                    const _B('Provide App services.'),
                    const _B('Comply with legal obligations.'),
                    const _B('Resolve disputes.'),
                    const _B('Enforce agreements.'),
                    const _P(
                      'You may request deletion of your account and data at any time.',
                    ),

                    // ── 9. Your Rights ───────────────────────────────────
                    const _H('9. Your Rights'),
                    const _P(
                      'Depending on your location, you may have the right to:',
                    ),
                    const _B('Access your personal data.'),
                    const _B('Correct inaccurate data.'),
                    const _B('Request deletion of your data.'),
                    const _B('Withdraw consent.'),
                    const _B('Object to data processing.'),
                    const _P('To exercise these rights, contact us at:'),
                    _EmailLink(email: _supportEmail),

                    // ── 10. Security ─────────────────────────────────────
                    const _H('10. Security'),
                    const _P(
                      'We implement appropriate technical and organizational measures '
                      'to protect your data. However, no system is 100% secure, and '
                      'we cannot guarantee absolute security.',
                    ),
                    const _P(
                      'You are responsible for keeping your account credentials safe.',
                    ),

                    // ── 11. Children's Privacy ───────────────────────────
                    const _H('11. Children\'s Privacy'),
                    const _P(
                      'The App is not intended for children under 13 years of age '
                      '(or the minimum legal age in your country). We do not '
                      'knowingly collect data from children.',
                    ),
                    const _P(
                      'If we discover such data has been collected, we will delete '
                      'it promptly.',
                    ),

                    // ── 12. Third-Party Services ─────────────────────────
                    const _H('12. Third-Party Services'),
                    const _P(
                      'The App may include third-party services such as:',
                    ),
                    const _B('Google/Firebase services.'),
                    const _B('Cloudinary image hosting.'),
                    const _B('External links or affiliate marketplaces.'),
                    const _P(
                      'These services operate under their own privacy policies, '
                      'which we encourage you to review.',
                    ),

                    // ── 13. Affiliate Links ──────────────────────────────
                    const _H('13. Affiliate Links'),
                    const _P(
                      'Some links in the App may be affiliate links. This means we '
                      'may earn a commission if you purchase through those links. '
                      'This does not affect the price you pay.',
                    ),

                    // ── 14. International Data Transfers ─────────────────
                    const _H('14. International Data Transfers'),
                    const _P(
                      'Your data may be processed in countries outside your location '
                      'where our service providers operate. We ensure appropriate '
                      'safeguards are applied where required by law.',
                    ),

                    // ── 15. Changes to This Policy ───────────────────────
                    const _H('15. Changes to This Policy'),
                    const _P(
                      'We may update this Privacy Policy from time to time. Updates '
                      'will be posted within the App, and the effective date will be '
                      'revised.',
                    ),
                    const _P(
                      'Continued use of the App means you accept the updated policy.',
                    ),

                    // ── 16. Contact Us ───────────────────────────────────
                    const _H('16. Contact Us'),
                    const _P(
                      'If you have any questions about this Privacy Policy, '
                      'contact us:',
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

/// Large section heading e.g. "1. Introduction"
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

/// Sub-section heading e.g. "2.1 Information you provide directly"
class _SubH extends StatelessWidget {
  const _SubH(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
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
