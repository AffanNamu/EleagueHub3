import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/locale/app_localizations.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _appName = 'eSportlyic';
  static const String _supportEmail = 'NASSARACORETECHVENTURES@GMAIL.COM';
  static const String _effectiveDate = '15 February 2026';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = l10n.tr('privacy_appbar_title');

    return GlassScaffold(
      appBar: AppBar(
        title: Text(title),
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
                  title: title,
                  subtitle: '$_appName${l10n.tr('privacy_subtitle_middle')}$_effectiveDate',
                  children: [
                    // ── 1. Introduction ──────────────────────────────────
                    _H(l10n.tr('privacy_h1')),
                    _P(
                      '${l10n.tr('privacy_s1_p1_prefix')}$_appName${l10n.tr('privacy_s1_p1_suffix')}',
                    ),
                    _P(l10n.tr('privacy_s1_p2')),

                    // ── 2. Information We Collect ────────────────────────
                    _H(l10n.tr('privacy_h2')),
                    _P(l10n.tr('privacy_s2_p1')),

                    _SubH(l10n.tr('privacy_s2_subh1')),
                    _B(l10n.tr('privacy_s2_b1')),
                    _B(l10n.tr('privacy_s2_b2')),
                    _B(l10n.tr('privacy_s2_b3')),
                    _B(l10n.tr('privacy_s2_b4')),

                    _SubH(l10n.tr('privacy_s2_subh2')),
                    _P(l10n.tr('privacy_s2_p2')),
                    _B(l10n.tr('privacy_s2_b5')),
                    _B(l10n.tr('privacy_s2_b6')),
                    _B(l10n.tr('privacy_s2_b7')),
                    _B(l10n.tr('privacy_s2_b8')),

                    _SubH(l10n.tr('privacy_s2_subh3')),
                    _P(l10n.tr('privacy_s2_p3')),
                    _B(l10n.tr('privacy_s2_b9')),
                    _B(l10n.tr('privacy_s2_b10')),
                    _B(l10n.tr('privacy_s2_b11')),
                    _B(l10n.tr('privacy_s2_b12')),
                    _P(l10n.tr('privacy_s2_p4')),

                    // ── 3. Camera / Microphone / Screen Recording ────────
                    _H(l10n.tr('privacy_h3')),
                    _P(l10n.tr('privacy_s3_p1')),
                    _B(l10n.tr('privacy_s3_b1')),
                    _B(l10n.tr('privacy_s3_b2')),
                    _B(l10n.tr('privacy_s3_b3')),
                    _P(l10n.tr('privacy_s3_p2')),

                    // ── 4. Overlay Permission ────────────────────────────
                    _H(l10n.tr('privacy_h4')),
                    _P(l10n.tr('privacy_s4_p1')),
                    _B(l10n.tr('privacy_s4_b1')),
                    _B(l10n.tr('privacy_s4_b2')),
                    _B(l10n.tr('privacy_s4_b3')),

                    // ── 5. How We Use Your Information ───────────────────
                    _H(l10n.tr('privacy_h5')),
                    _P(l10n.tr('privacy_s5_p1')),
                    _B(l10n.tr('privacy_s5_b1')),
                    _B(l10n.tr('privacy_s5_b2')),
                    _B(l10n.tr('privacy_s5_b3')),
                    _B(l10n.tr('privacy_s5_b4')),
                    _B(l10n.tr('privacy_s5_b5')),
                    _B(l10n.tr('privacy_s5_b6')),
                    _B(l10n.tr('privacy_s5_b7')),

                    // ── 6. Data Storage and Services ────────────────────
                    _H(l10n.tr('privacy_h6')),
                    _P(l10n.tr('privacy_s6_p1')),
                    _B(l10n.tr('privacy_s6_b1')),
                    _B(l10n.tr('privacy_s6_b2')),
                    _P(l10n.tr('privacy_s6_p2')),

                    // ── 7. Sharing of Information ────────────────────────
                    _H(l10n.tr('privacy_h7')),
                    _P(l10n.tr('privacy_s7_p1')),
                    _P(l10n.tr('privacy_s7_p2')),
                    _B(l10n.tr('privacy_s7_b1')),
                    _B(l10n.tr('privacy_s7_b2')),
                    _B(l10n.tr('privacy_s7_b3')),
                    _B(l10n.tr('privacy_s7_b4')),

                    // ── 8. Data Retention ────────────────────────────────
                    _H(l10n.tr('privacy_h8')),
                    _P(l10n.tr('privacy_s8_p1')),
                    _B(l10n.tr('privacy_s8_b1')),
                    _B(l10n.tr('privacy_s8_b2')),
                    _B(l10n.tr('privacy_s8_b3')),
                    _B(l10n.tr('privacy_s8_b4')),
                    _P(l10n.tr('privacy_s8_p2')),

                    // ── 9. Your Rights ───────────────────────────────────
                    _H(l10n.tr('privacy_h9')),
                    _P(l10n.tr('privacy_s9_p1')),
                    _B(l10n.tr('privacy_s9_b1')),
                    _B(l10n.tr('privacy_s9_b2')),
                    _B(l10n.tr('privacy_s9_b3')),
                    _B(l10n.tr('privacy_s9_b4')),
                    _B(l10n.tr('privacy_s9_b5')),
                    _P(l10n.tr('privacy_s9_p2')),
                    _EmailLink(email: _supportEmail),

                    // ── 10. Security ─────────────────────────────────────
                    _H(l10n.tr('privacy_h10')),
                    _P(l10n.tr('privacy_s10_p1')),
                    _P(l10n.tr('privacy_s10_p2')),

                    // ── 11. Children's Privacy ───────────────────────────
                    _H(l10n.tr('privacy_h11')),
                    _P(l10n.tr('privacy_s11_p1')),
                    _P(l10n.tr('privacy_s11_p2')),

                    // ── 12. Third-Party Services ─────────────────────────
                    _H(l10n.tr('privacy_h12')),
                    _P(l10n.tr('privacy_s12_p1')),
                    _B(l10n.tr('privacy_s12_b1')),
                    _B(l10n.tr('privacy_s12_b2')),
                    _B(l10n.tr('privacy_s12_b3')),
                    _P(l10n.tr('privacy_s12_p2')),

                    // ── 13. Affiliate Links ──────────────────────────────
                    _H(l10n.tr('privacy_h13')),
                    _P(l10n.tr('privacy_s13_p1')),

                    // ── 14. International Data Transfers ─────────────────
                    _H(l10n.tr('privacy_h14')),
                    _P(l10n.tr('privacy_s14_p1')),

                    // ── 15. Changes to This Policy ───────────────────────
                    _H(l10n.tr('privacy_h15')),
                    _P(l10n.tr('privacy_s15_p1')),
                    _P(l10n.tr('privacy_s15_p2')),

                    // ── 16. Contact Us ───────────────────────────────────
                    _H(l10n.tr('privacy_h16')),
                    _P(l10n.tr('privacy_s16_p1')),
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
