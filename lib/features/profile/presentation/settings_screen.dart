import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/platform/overlay_platform.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../live/logic/quick_message_policy.dart';
import '../../live/logic/quick_messages_controller.dart';
import '../../master_leagues/domain/master_league.dart';
import '../../master_leagues/logic/master_leagues_providers.dart';

String _trOr(AppLocalizations l10n, String key, String fallback) {
  final v = l10n.tr(key);
  return v == key ? fallback : v;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _enabled = true;
  bool _marketing = false;
  bool _matchReminders = true;

  bool _overlayEnabled = false;
  bool _overlayPermissionGranted = false;

  static const int _quickMaxChars = 15;

  final TextEditingController _quickInput = TextEditingController();
  bool _savingQuick = false;
  bool _verificationBusy = false;

  static const Map<String, String> _languageAutonyms = {
    'en': 'English',
    'fr': 'Français',
    'es': 'Español',
    'ru': 'Русский',
    'sw': 'Kiswahili',
    'ar': 'العربية',
    'he': 'עברית',
    'ja': '日本語',
    'ko': '한국어',
    'pt': 'Português',
    'id': 'Bahasa Indonesia',
    'tr': 'Türkçe',
  };

  static bool _isRtlLangCode(String code) => code == 'ar' || code == 'he';

  String _languageDisplayName(String code) =>
      _languageAutonyms[code] ?? code.toUpperCase();

  TextDirection _languageTextDirection(String code) =>
      _isRtlLangCode(code) ? TextDirection.rtl : TextDirection.ltr;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quickInput.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOverlayPermissionAndMaybeStart());
    }
  }

  Future<void> _load() async {
    final prefs = ref.read(prefsServiceProvider);
    final map = await prefs.loadNotificationPrefs();
    final overlay = prefs.liveOverlayEnabled();
    final granted = await OverlayPlatform.isOverlayPermissionGranted();

    if (!mounted) return;
    setState(() {
      _enabled = map['enabled'] ?? true;
      _marketing = map['marketing'] ?? false;
      _matchReminders = map['matchReminders'] ?? true;
      _overlayEnabled = overlay;
      _overlayPermissionGranted = granted;
      _loading = false;
    });

    if (_overlayEnabled && _overlayPermissionGranted) {
      await OverlayPlatform.startGlobalOverlay();
    }
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    final text = message.trim();
    if (text.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _saveNotifications() async {
    final prefs = ref.read(prefsServiceProvider);
    await prefs.saveNotificationPrefs(
      enabled: _enabled,
      marketing: _marketing,
      matchReminders: _matchReminders,
    );
  }

  Future<void> _refreshOverlayPermissionAndMaybeStart() async {
    final granted = await OverlayPlatform.isOverlayPermissionGranted();
    if (!mounted) return;
    setState(() => _overlayPermissionGranted = granted);
    if (_overlayEnabled && granted) {
      await OverlayPlatform.startGlobalOverlay();
    }
  }

  Future<void> _setOverlayEnabled(bool enabled) async {
    final prefs = ref.read(prefsServiceProvider);

    if (!enabled) {
      setState(() => _overlayEnabled = false);
      await prefs.setLiveOverlayEnabled(false);
      await OverlayPlatform.stopGlobalOverlay();
      return;
    }

    setState(() => _overlayEnabled = true);
    await prefs.setLiveOverlayEnabled(true);

    final granted = await OverlayPlatform.isOverlayPermissionGranted();
    if (!mounted) return;
    setState(() => _overlayPermissionGranted = granted);

    if (granted) {
      await OverlayPlatform.startGlobalOverlay();
      return;
    }

    final l10n = context.l10n;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _trOr(
            l10n,
            'live_overlay_permission_title',
            'Allow overlay permission',
          ),
        ),
        content: Text(
          _trOr(
            l10n,
            'live_overlay_permission_body',
            'To show the floating voice/message controls above other apps, Android requires an "Appear on top" permission.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(_trOr(l10n, 'common_cancel', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(_trOr(l10n, 'common_open_settings', 'Open settings')),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    await OverlayPlatform.requestOverlayPermission();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          _trOr(
            l10n,
            'live_overlay_permission_snackbar',
            'Grant the overlay permission, then return to the app.',
          ),
        ),
      ),
    );
  }

  Future<void> _addCustomQuickMessage() async {
    if (_savingQuick) return;
    final l10n = context.l10n;

    final input = _quickInput.text.trim();

    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _trOr(l10n, 'quick_messages_empty_toast', 'Enter a message first.'),
          ),
        ),
      );
      return;
    }

    if (input.runes.length > _quickMaxChars) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _trOr(
              l10n,
              'quick_messages_too_long_toast',
              'Max $_quickMaxChars characters.',
            ),
          ),
        ),
      );
      return;
    }

    setState(() => _savingQuick = true);
    try {
      await ref.read(quickMessagesControllerProvider).addCustomMessage(input);
      _quickInput.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(_trOr(l10n, 'quick_messages_added_toast', 'Added')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingQuick = false);
    }
  }

  Future<void> _deleteCustomQuickMessage(int index) async {
    try {
      await ref.read(quickMessagesControllerProvider).deleteCustomMessageAt(index);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<MasterLeague?> _resolveVerificationWorkspace(
    List<MasterLeague> items,
  ) async {
    if (items.isEmpty) return null;

    for (final item in items) {
      if (!item.isVerifiedOrganizer && !item.isVerificationPending) {
        return item;
      }
    }

    for (final item in items) {
      if (item.verificationExpired && item.canRenewVerification) {
        return item;
      }
    }

    return items.first;
  }

  Future<void> _handleVerificationAction(MasterLeague workspace) async {
    if (_verificationBusy) return;

    setState(() => _verificationBusy = true);
    try {
      final paymentSvc = ref.read(masterLeaguePaymentServiceProvider);
      final repo = ref.read(masterLeaguesRepositoryProvider);
      final userId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

      if (workspace.isVerifiedOrganizer) {
        _snack('This organizer is already verified.');
        return;
      }

      if (workspace.canRenewVerification &&
          !workspace.isVerificationPending &&
          workspace.verificationExpired) {
        final payment = await paymentSvc.payForOrganizerVerificationRenewal(
          context: context,
          userId: userId,
          masterLeagueId: workspace.id,
          masterLeagueName: workspace.name,
        );

        if (!mounted) return;

        if (!payment.success) {
          _snack(
            payment.errorMessage ?? 'Verification renewal payment failed.',
            error: true,
          );
          return;
        }

        await repo.submitVerificationRenewalRequest(
          masterLeagueId: workspace.id,
          attemptId: payment.attemptId,
          paymentId: payment.paymentId,
          receiptId: payment.receiptId ?? '',
          note: '',
        );

        ref.invalidate(createdMasterLeaguesProvider);
        ref.invalidate(masterLeagueByIdProvider(workspace.id));
        _snack('Verification renewal request submitted.');
        return;
      }

      if (!workspace.isVerificationPending) {
        final payment = await paymentSvc.payForOrganizerVerification(
          context: context,
          userId: userId,
          masterLeagueId: workspace.id,
          masterLeagueName: workspace.name,
        );

        if (!mounted) return;

        if (!payment.success) {
          _snack(
            payment.errorMessage ?? 'Verification payment failed.',
            error: true,
          );
          return;
        }

        await repo.submitVerificationRequest(
          masterLeagueId: workspace.id,
          attemptId: payment.attemptId,
          paymentId: payment.paymentId,
          receiptId: payment.receiptId ?? '',
          note: '',
        );

        ref.invalidate(createdMasterLeaguesProvider);
        ref.invalidate(masterLeagueByIdProvider(workspace.id));
        _snack('Verification request submitted.');
        return;
      }

      _snack('A verification request is already pending review.');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _verificationBusy = false);
    }
  }

  String _themeModeLabel(ThemeMode mode, AppLocalizations l10n) {
    switch (mode) {
      case ThemeMode.system:
        return l10n.themeSystem;
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return l10n.themeDark;
    }
  }

  IconData _themeModeIcon(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons.brightness_auto_rounded;
      case ThemeMode.light:
        return Icons.light_mode_rounded;
      case ThemeMode.dark:
        return Icons.dark_mode_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final onSurface = cs.onSurface;

    final themeState = ref.watch(themeControllerProvider);
    final localeState = ref.watch(localeControllerProvider);

    final currentLangCode = localeState.locale.languageCode;
    final supportedCodes = LocaleController.supportedLanguageCodes;

    final overlayStatusText = !_overlayEnabled
        ? _trOr(l10n, 'live_overlay_status_off', 'Overlay: Off')
        : (_overlayPermissionGranted
            ? _trOr(l10n, 'live_overlay_status_on', 'Overlay: On')
            : _trOr(
                l10n,
                'live_overlay_status_needs_permission',
                'Overlay: Permission required',
              ));

    final premium = ref.watch(isPremiumProvider).value ?? false;
    final customQuick = ref.watch(inAppCustomQuickMessagesProvider);
    final createdMasterLeaguesAsync = ref.watch(createdMasterLeaguesProvider);

    return GlassScaffold(
      appBar: AppBar(
        title: const Text(''),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Glass(
            padding: const EdgeInsets.all(8),
            borderRadius: 12,
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 18,
              color: onSurface.withOpacity(0.9),
            ),
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 100),
              children: [
                Glass(
                  borderRadius: 22,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              cs.primary.withOpacity(0.30),
                              cs.primary.withOpacity(0.08),
                            ],
                          ),
                        ),
                        child: Icon(
                          Icons.settings_rounded,
                          color: cs.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.settingsTitle,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                letterSpacing: -0.5,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Customize your experience',
                              style: TextStyle(
                                color: onSurface.withOpacity(0.55),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _SectionLabel(
                  icon: Icons.verified_user_rounded,
                  label: 'Verification',
                ),
                const SizedBox(height: 8),
                createdMasterLeaguesAsync.when(
                  loading: () => Glass(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(16),
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Glass(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '$e',
                      style: TextStyle(
                        color: cs.error,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  data: (items) {
                    if (items.isEmpty) {
                      return Glass(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Create an organizer workspace first before requesting verification.',
                          style: TextStyle(
                            color: onSurface.withOpacity(0.68),
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      );
                    }

                    return FutureBuilder<MasterLeague?>(
                      future: _resolveVerificationWorkspace(items),
                      builder: (context, snap) {
                        final workspace = snap.data;

                        if (workspace == null) {
                          return Glass(
                            borderRadius: 20,
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'No organizer workspace is currently available for verification.',
                              style: TextStyle(
                                color: onSurface.withOpacity(0.68),
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                            ),
                          );
                        }

                        Color statusColor;
                        IconData statusIcon;
                        String statusTitle;
                        String statusSubtitle;
                        String actionLabel = '';

                        if (workspace.isVerifiedOrganizer) {
                          statusColor = const Color(0xFF1D9BF0);
                          statusIcon = Icons.verified_rounded;
                          statusTitle = 'Verified';
                          statusSubtitle =
                              'Your organizer is already verified.';
                        } else if (workspace.isVerificationPending) {
                          statusColor = const Color(0xFFF59E0B);
                          statusIcon = Icons.hourglass_top_rounded;
                          statusTitle = 'Verification Pending';
                          statusSubtitle =
                              'Your verification request is currently under review.';
                        } else if (workspace.verificationExpired &&
                            workspace.canRenewVerification) {
                          statusColor = const Color(0xFFF59E0B);
                          statusIcon = Icons.refresh_rounded;
                          statusTitle = 'Verification Expired';
                          statusSubtitle =
                              'Renew your organizer verification to restore the verified badge.';
                          actionLabel = 'Get Verified';
                        } else {
                          statusColor = onSurface.withOpacity(0.60);
                          statusIcon = Icons.verified_outlined;
                          statusTitle = 'Not Verified';
                          statusSubtitle =
                              'Get verified to show trust and authenticity beside your organizer name.';
                          actionLabel = 'Get Verified';
                        }

                        final canPress = !workspace.isVerifiedOrganizer &&
                            !workspace.isVerificationPending;

                        return Glass(
                          borderRadius: 20,
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: statusColor.withOpacity(0.12),
                                      border: Border.all(
                                        color: statusColor.withOpacity(0.24),
                                      ),
                                    ),
                                    child: Icon(statusIcon, color: statusColor),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          statusTitle,
                                          style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          workspace.name.trim().isEmpty
                                              ? 'Organizer Workspace'
                                              : workspace.name.trim(),
                                          style: TextStyle(
                                            color: onSurface,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                statusSubtitle,
                                style: TextStyle(
                                  color: onSurface.withOpacity(0.62),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                              if (canPress) ...[
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: _verificationBusy
                                        ? null
                                        : () => _handleVerificationAction(
                                              workspace,
                                            ),
                                    icon: _verificationBusy
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(
                                            workspace.verificationExpired
                                                ? Icons.refresh_rounded
                                                : Icons.verified_user_outlined,
                                          ),
                                    label: Text(
                                      _verificationBusy
                                          ? 'Processing...'
                                          : actionLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),

                const SizedBox(height: 16),

                _SectionLabel(icon: Icons.palette_rounded, label: l10n.themeTitle),
                const SizedBox(height: 8),
                Glass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          for (final mode in ThemeMode.values) ...[
                            if (mode != ThemeMode.values.first)
                              const SizedBox(width: 8),
                            Expanded(
                              child: _ThemeModeCard(
                                icon: _themeModeIcon(mode),
                                label: _themeModeLabel(mode, l10n),
                                selected: themeState.mode == mode,
                                onTap: () async {
                                  await ref
                                      .read(themeControllerProvider.notifier)
                                      .setThemeMode(mode);
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.themeHint,
                        style: TextStyle(
                          color: onSurface.withOpacity(0.50),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _SectionLabel(
                  icon: Icons.language_rounded,
                  label: l10n.languageTitle,
                ),
                const SizedBox(height: 8),
                Glass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.languageHint,
                        style: TextStyle(
                          color: onSurface.withOpacity(0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _showLanguagePicker(
                          context,
                          supportedCodes,
                          currentLangCode,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: onSurface.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: onSurface.withOpacity(0.10),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.translate_rounded,
                                color: cs.primary,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Directionality(
                                  textDirection:
                                      _languageTextDirection(currentLangCode),
                                  child: Text(
                                    _languageDisplayName(currentLangCode),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: onSurface,
                                    ),
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: onSurface.withOpacity(0.35),
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _SectionLabel(
                  icon: Icons.notifications_rounded,
                  label: l10n.notificationsTitle,
                ),
                const SizedBox(height: 8),
                Glass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(16),
                  child: _loading
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: CircularProgressIndicator(
                              color: cs.primary,
                              strokeWidth: 2,
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            _SettingsToggle(
                              icon: Icons.notifications_active_rounded,
                              title: l10n.notificationsEnabledTitle,
                              subtitle: l10n.notificationsEnabledSubtitle,
                              value: _enabled,
                              onChanged: (v) async {
                                setState(() => _enabled = v);
                                await _saveNotifications();
                                if (v) {
                                  await NotificationService().showTestNotification();
                                }
                              },
                            ),
                            Divider(color: onSurface.withOpacity(0.08), height: 1),
                            _SettingsToggle(
                              icon: Icons.alarm_rounded,
                              title: l10n.notificationsMatchRemindersTitle,
                              subtitle:
                                  l10n.notificationsMatchRemindersSubtitle,
                              value: _matchReminders,
                              enabled: _enabled,
                              onChanged: (v) async {
                                setState(() => _matchReminders = v);
                                await _saveNotifications();
                              },
                            ),
                            Divider(color: onSurface.withOpacity(0.08), height: 1),
                            _SettingsToggle(
                              icon: Icons.campaign_rounded,
                              title: l10n.notificationsMarketingTitle,
                              subtitle: l10n.notificationsMarketingSubtitle,
                              value: _marketing,
                              enabled: _enabled,
                              onChanged: (v) async {
                                setState(() => _marketing = v);
                                await _saveNotifications();
                              },
                            ),
                          ],
                        ),
                ),

                const SizedBox(height: 16),

                _SectionLabel(
                  icon: Icons.picture_in_picture_alt_rounded,
                  label: l10n.liveOverlayTitle,
                ),
                const SizedBox(height: 8),
                Glass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.liveOverlayHint,
                        style: TextStyle(
                          color: onSurface.withOpacity(0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _OverlayStatusCard(
                        enabled: _overlayEnabled,
                        granted: _overlayPermissionGranted,
                        statusText: overlayStatusText,
                        onGrant: () async {
                          await OverlayPlatform.requestOverlayPermission();
                        },
                      ),
                      const SizedBox(height: 10),
                      _SettingsToggle(
                        icon: Icons.layers_rounded,
                        title: l10n.liveOverlaySwitchTitle,
                        subtitle: l10n.liveOverlaySwitchSubtitle,
                        value: _overlayEnabled,
                        onChanged: (v) async => _setOverlayEnabled(v),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _SectionLabel(
                  icon: Icons.chat_bubble_rounded,
                  label: _trOr(l10n, 'quick_messages_title', 'Quick Messages'),
                ),
                const SizedBox(height: 8),
                Glass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _trOr(
                                l10n,
                                'quick_messages_hint',
                                'Defaults are included. Premium users can add up to 15 custom quick messages.',
                              ),
                              style: TextStyle(
                                color: onSurface.withOpacity(0.55),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _PremiumBadge(isPremium: premium),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (!premium) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: onSurface.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: onSurface.withOpacity(0.08)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.amber.withOpacity(0.12),
                                ),
                                child: const Icon(
                                  Icons.lock_outline_rounded,
                                  color: Colors.amber,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _trOr(
                                    l10n,
                                    'quick_messages_premium_required',
                                    'Premium required to create custom quick messages.',
                                  ),
                                  style: TextStyle(
                                    color: onSurface.withOpacity(0.70),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        behavior: SnackBarBehavior.floating,
                                        content: Text(
                                          _trOr(
                                            l10n,
                                            'quick_messages_upgrade_soon',
                                            'Upgrade flow not implemented yet.',
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Ink(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: cs.primary.withOpacity(0.12),
                                      border: Border.all(
                                        color: cs.primary.withOpacity(0.25),
                                      ),
                                    ),
                                    child: Text(
                                      _trOr(l10n, 'common_upgrade', 'Upgrade'),
                                      style: TextStyle(
                                        color: cs.primary,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        if (customQuick.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: onSurface.withOpacity(0.35),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _trOr(
                                    l10n,
                                    'quick_messages_none_yet',
                                    'No custom messages yet. Add one below.',
                                  ),
                                  style: TextStyle(
                                    color: onSurface.withOpacity(0.55),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: customQuick.length,
                            onReorder: (oldIndex, newIndex) async {
                              if (newIndex > oldIndex) newIndex -= 1;
                              try {
                                await ref
                                    .read(quickMessagesControllerProvider)
                                    .reorderCustom(oldIndex, newIndex);
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    content: Text(
                                      e.toString().replaceFirst('Exception: ', ''),
                                    ),
                                  ),
                                );
                              }
                            },
                            itemBuilder: (ctx, i) {
                              final msg = customQuick[i];
                              return _QuickMessageTile(
                                key: ValueKey('custom_quick_$i:$msg'),
                                message: msg,
                                onDelete: () => _deleteCustomQuickMessage(i),
                              );
                            },
                          ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _quickInput,
                                maxLength: _quickMaxChars,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(_quickMaxChars),
                                ],
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) =>
                                    _savingQuick ? null : _addCustomQuickMessage(),
                                style: TextStyle(
                                  color: onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: InputDecoration(
                                  counterText: '',
                                  hintText: _trOr(
                                    l10n,
                                    'quick_messages_add_hint',
                                    'Add custom message…',
                                  ),
                                  helperText: 'Max $_quickMaxChars chars',
                                  hintStyle:
                                      TextStyle(color: onSurface.withOpacity(0.45)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: _savingQuick ? null : _addCustomQuickMessage,
                                borderRadius: BorderRadius.circular(12),
                                child: Ink(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                      colors: [
                                        cs.primary,
                                        cs.primary.withOpacity(0.75),
                                      ],
                                    ),
                                  ),
                                  child: Center(
                                    child: _savingQuick
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.add_rounded,
                                            color: Colors.white,
                                            size: 22,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                _SectionLabel(
                  icon: Icons.info_outline_rounded,
                  label: l10n.appInfoTitle,
                ),
                const SizedBox(height: 8),
                Glass(
                  borderRadius: 20,
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              cs.primary.withOpacity(0.25),
                              cs.primary.withOpacity(0.08),
                            ],
                          ),
                        ),
                        child: Icon(
                          Icons.sports_esports_rounded,
                          color: cs.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'eSportlyic',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Powered by Kaida',
                              style: TextStyle(
                                color: onSurface.withOpacity(0.50),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker(
    BuildContext context,
    List<String> codes,
    String current,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        final onSurface = cs.onSurface;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Glass(
                  borderRadius: 26,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(top: 8, bottom: 14),
                        decoration: BoxDecoration(
                          color: onSurface.withOpacity(0.20),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          ctx.l10n.languageTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 400),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const BouncingScrollPhysics(),
                          itemCount: codes.length,
                          itemBuilder: (context, i) {
                            final code = codes[i];
                            final selected = code == current;

                            return InkWell(
                              onTap: () async {
                                Navigator.of(ctx).pop();
                                await ref
                                    .read(localeControllerProvider.notifier)
                                    .setLocale(code);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 14,
                                ),
                                color: selected
                                    ? cs.primary.withOpacity(0.08)
                                    : Colors.transparent,
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Directionality(
                                        textDirection:
                                            _languageTextDirection(code),
                                        child: Text(
                                          _languageDisplayName(code),
                                          style: TextStyle(
                                            fontWeight: selected
                                                ? FontWeight.w900
                                                : FontWeight.w600,
                                            color: selected
                                                ? cs.primary
                                                : onSurface.withOpacity(0.80),
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      Icon(
                                        Icons.check_circle_rounded,
                                        color: cs.primary,
                                        size: 20,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.primary.withOpacity(0.7)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              letterSpacing: -0.2,
              color: onSurface.withOpacity(0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeCard extends StatelessWidget {
  const _ThemeModeCard({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final color = selected ? cs.primary : onSurface.withOpacity(0.65);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? cs.primary.withOpacity(0.12)
              : onSurface.withOpacity(0.04),
          border: Border.all(
            color: selected
                ? cs.primary.withOpacity(0.35)
                : onSurface.withOpacity(0.10),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onSurface = cs.onSurface;
    final effectiveOpacity = enabled ? 1.0 : 0.4;

    return Opacity(
      opacity: effectiveOpacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary.withOpacity(0.10),
              ),
              child: Icon(icon, color: cs.primary, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: onSurface.withOpacity(0.55),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: cs.primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayStatusCard extends StatelessWidget {
  const _OverlayStatusCard({
    required this.enabled,
    required this.granted,
    required this.statusText,
    required this.onGrant,
  });

  final bool enabled;
  final bool granted;
  final String statusText;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final Color color;
    final IconData icon;

    if (!enabled) {
      color = onSurface.withOpacity(0.55);
      icon = Icons.info_outline_rounded;
    } else if (granted) {
      color = const Color(0xFF00E676);
      icon = Icons.check_circle_outline_rounded;
    } else {
      color = const Color(0xFFF59E0B);
      icon = Icons.warning_amber_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          if (enabled && !granted)
            InkWell(
              onTap: onGrant,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Grant',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge({required this.isPremium});
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color =
        isPremium ? const Color(0xFF00E676) : onSurface.withOpacity(0.55);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(
        isPremium ? 'PREMIUM' : 'LOCKED',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _QuickMessageTile extends StatelessWidget {
  const _QuickMessageTile({
    super.key,
    required this.message,
    required this.onDelete,
  });

  final String message;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: onSurface.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.drag_handle_rounded,
            color: onSurface.withOpacity(0.35),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: onSurface,
              ),
            ),
          ),
          InkWell(
            onTap: onDelete,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent.withOpacity(0.7),
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
