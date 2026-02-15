import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _appName = 'eLeagueHub';
  static const String _supportEmail = 'support-esportlyic@kainuwa.africa';
  static const String _effectiveDate = '15 February 2026';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
      ),
      backgroundColor: cs.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: _LegalDoc(
                title: 'Privacy Policy',
                subtitle: 'Effective date: $_effectiveDate',
                children: const [
                  _P(
                    'This Privacy Policy explains how $_appName (the “App”, “we”, “us”, or “our”) collects, uses, shares, and protects information when you use the App and related services. '
                    'By using the App, you agree to the practices described in this Privacy Policy.',
                  ),
                  _H('1) Who we are'),
                  _P(
                    '$_appName is a league management application that enables users to create accounts, manage profiles, create/manage leagues, and interact with marketplace content that may include affiliate links.',
                  ),
                  _H('2) Information we collect'),
                  _P(
                    'We collect information in the following ways:',
                  ),
                  _B(
                    'Information you provide: account and profile information (such as team name), support requests, and any content you submit within the App.',
                  ),
                  _B(
                    'Information collected automatically: limited technical data such as device information, app version, crash logs, and diagnostic data to help maintain security and performance.',
                  ),
                  _B(
                    'Information from third parties: where you choose to sign in via supported identity providers (e.g., Google), we receive authentication identifiers and basic profile details from that provider as permitted by your settings and their policies.',
                  ),
                  _H('3) Firebase Authentication data'),
                  _P(
                    'We use Firebase Authentication to sign you in and to secure access to your account. Depending on the sign-in method, Firebase Authentication may process data such as:',
                  ),
                  _B('A unique user identifier (UID).'),
                  _B('Email address (if you sign in with email or a provider that shares email).'),
                  _B('Display name and profile photo URL (if available).'),
                  _B('Authentication tokens and security-related metadata.'),
                  _P(
                    'Authentication data is used to authenticate you, protect your account, prevent abuse, and provide account-related features. '
                    'Firebase processes this information under its own terms and privacy policy.',
                  ),
                  _H('4) User profile data'),
                  _P(
                    'If you create or update a profile within the App, we may store profile-related information in our backend (such as Cloud Firestore). This can include:',
                  ),
                  _B('Team name and public-facing profile identifiers.'),
                  _B('Profile photo URL and related image references.'),
                  _B('App feature configuration linked to your account (e.g., preferences or league-related settings).'),
                  _P(
                    'We use this information to display your profile, enable league features, and support the functionality of the App.',
                  ),
                  _H('5) Cloudinary image storage'),
                  _P(
                    'When you upload images (such as an avatar/profile photo), the image may be uploaded to Cloudinary for storage and delivery. '
                    'Cloudinary may receive your uploaded image and related technical metadata required to store and deliver the image (for example, file type, size, and delivery URLs).',
                  ),
                  _P(
                    'Images are used to display your profile/team visuals inside the App. You can remove or replace your uploaded images in the App where supported. '
                    'Removal in the App updates our stored references; cached copies may persist for a limited time due to CDN caching.',
                  ),
                  _H('6) Affiliate links and marketplace content'),
                  _P(
                    'The App may include marketplace content and links to third-party stores or partner sites. Some links may be affiliate links, meaning we may earn a commission if you make a purchase through those links.',
                  ),
                  _P(
                    'When you click an affiliate link, you may be redirected to an external site that is governed by its own privacy policy and terms. '
                    'We do not control how third-party sites collect or use your information.',
                  ),
                  _H('7) Analytics and diagnostics'),
                  _P(
                    'We use diagnostics tools to maintain and improve the App. This may include Firebase Crashlytics (and, where enabled, analytics events) to understand stability, performance, and how features are used. '
                    'These tools may collect technical identifiers, app interaction data, and crash reports. We use this information to:',
                  ),
                  _B('Detect, prevent, and fix crashes and bugs.'),
                  _B('Improve reliability, performance, and user experience.'),
                  _B('Monitor security and potential abuse.'),
                  _H('8) How we use information'),
                  _P(
                    'We may use collected information to:',
                  ),
                  _B('Provide, operate, and maintain the App and its features.'),
                  _B('Authenticate users and secure accounts.'),
                  _B('Process and display user profile content, including images.'),
                  _B('Communicate with you about support requests and important service updates.'),
                  _B('Enforce our Terms of Service and prevent fraud or abuse.'),
                  _B('Comply with legal obligations.'),
                  _H('9) How we share information'),
                  _P(
                    'We do not sell your personal information. We may share information only in the following circumstances:',
                  ),
                  _B(
                    'Service providers: with vendors who help us operate the App (for example, Firebase/Google for authentication and database services, Cloudinary for image storage/delivery).',
                  ),
                  _B(
                    'Legal and safety: if required by law, legal process, or to protect the rights, property, and safety of users, the public, or our services.',
                  ),
                  _B(
                    'Business changes: if we are involved in a merger, acquisition, financing, reorganization, bankruptcy, or sale of assets, information may be transferred as part of that transaction, subject to applicable law.',
                  ),
                  _H('10) Data protection and security'),
                  _P(
                    'We implement reasonable administrative, technical, and organizational safeguards designed to protect information against unauthorized access, alteration, disclosure, or destruction. '
                    'No method of transmission or storage is 100% secure. You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account.',
                  ),
                  _H('11) Data retention'),
                  _P(
                    'We retain information for as long as needed to provide the App and for legitimate business purposes such as security, compliance, dispute resolution, and enforcement of agreements. '
                    'If you request deletion, we will take reasonable steps to delete or de-identify personal information, unless we are required to retain certain data for legal or security reasons.',
                  ),
                  _H('12) Your rights and choices'),
                  _P(
                    'Depending on your location and applicable law, you may have rights to:',
                  ),
                  _B('Access the personal information we hold about you.'),
                  _B('Correct inaccurate or incomplete information.'),
                  _B('Request deletion of your information.'),
                  _B('Object to or restrict certain processing.'),
                  _B('Withdraw consent where processing is based on consent.'),
                  _P(
                    'To exercise these rights, contact us at $_supportEmail. We may need to verify your identity before fulfilling certain requests.',
                  ),
                  _H('13) Third-party services'),
                  _P(
                    'The App relies on third-party services that may process information to provide their functionality. These may include (but are not limited to):',
                  ),
                  _B('Google/Firebase (Authentication, Cloud Firestore, Crashlytics and related infrastructure).'),
                  _B('Cloudinary (image storage and delivery).'),
                  _B('External affiliate/partner stores (when you click outbound links).'),
                  _P(
                    'Your use of third-party services is subject to their terms and privacy policies. We encourage you to review them.',
                  ),
                  _H('14) Children’s privacy'),
                  _P(
                    'The App is not directed to children under the age of 13 (or a higher age where required by local law). '
                    'We do not knowingly collect personal information from children. If you believe a child has provided personal information, contact us so we can take appropriate action.',
                  ),
                  _H('15) International transfers'),
                  _P(
                    'Your information may be processed and stored in countries other than your own, including where our service providers maintain facilities. '
                    'We take steps designed to ensure that transfers comply with applicable data protection laws.',
                  ),
                  _H('16) Changes to this Privacy Policy'),
                  _P(
                    'We may update this Privacy Policy from time to time. We will post the updated version in the App and update the effective date above. '
                    'Your continued use of the App after changes become effective means you accept the updated Privacy Policy.',
                  ),
                  _H('17) Contact us'),
                  _P(
                    'If you have any questions about this Privacy Policy or our privacy practices, contact us:',
                  ),
                  _P('Email: $_supportEmail'),
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
