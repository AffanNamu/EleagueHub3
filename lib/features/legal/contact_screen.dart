import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  static const String supportEmail = 'support-esportlyic@kainuwa.africa';

  Future<void> _launchSupportEmail(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: <String, String>{
        'subject': 'eLeagueHub Support Request',
        'body':
            'Hello Support,\n\nPlease describe your issue and include:\n- What you were trying to do\n- Any error message you saw\n- Your device model and OS version\n\nThanks,\n',
      },
    );

    try {
      final ok = await canLaunchUrl(uri);
      if (!ok) {
        messenger.clearSnackBars();
        messenger.showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(12),
            content: Text('No email app found to send this message.'),
          ),
        );
        return;
      }

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        messenger.clearSnackBars();
        messenger.showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(12),
            content: Text('Could not open your email app.'),
          ),
        );
      }
    } catch (_) {
      messenger.clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(12),
          content: Text('Could not open your email app.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact'),
      ),
      backgroundColor: cs.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Support',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onBackground,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'If you need help with your account, leagues, payments, or marketplace links, contact us and we’ll respond as soon as possible.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onBackground.withOpacity(0.85),
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 0,
                    color: cs.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: cs.onSurface.withOpacity(0.10)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _InfoRow(
                            icon: Icons.email_outlined,
                            title: 'Email',
                            value: supportEmail,
                            onCopy: () async {
                              await Clipboard.setData(
                                const ClipboardData(text: supportEmail),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  behavior: SnackBarBehavior.floating,
                                  margin: EdgeInsets.all(12),
                                  content: Text('Support email copied.'),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          const _InfoRow(
                            icon: Icons.phone_outlined,
                            title: 'Phone (optional)',
                            value: 'Not available',
                            onCopy: null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _launchSupportEmail(context),
                    icon: const Icon(Icons.support_agent),
                    label: const Text('Contact Support'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tip: For faster support, include screenshots and the steps to reproduce the issue.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onBackground.withOpacity(0.70),
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onCopy,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Icon(icon, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withOpacity(0.70),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (onCopy != null)
          IconButton(
            tooltip: 'Copy',
            onPressed: onCopy,
            icon: Icon(Icons.copy, color: cs.onSurface.withOpacity(0.70)),
          ),
      ],
    );
  }
}
