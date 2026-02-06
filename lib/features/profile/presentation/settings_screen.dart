import 'dart:async';

import 'package:flutter/material.dart';
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

String _trOr(AppLocalizations l10n, String key, String fallback) {
  final v = l10n.tr(key);
  return v == key ? fallback : v;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> with WidgetsBindingObserver {
  bool _loading = true;
  bool _enabled = true;
  bool _marketing = false;
  bool _matchReminders = true;

  bool _overlayEnabled = false;
  bool _overlayPermissionGranted = false;

  final TextEditingController _quickInput = TextEditingController();
  bool _savingQuick = false;

  /// Autonyms (language names in their own language).
  /// IMPORTANT: These should NOT be translated based on current app locale.
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

  String _languageDisplayName(String code) {
    return _languageAutonyms[code] ?? code.toUpperCase();
  }

  TextDirection _languageTextDirection(String code) {
    return _isRtlLangCode(code) ? TextDirection.rtl : TextDirection.ltr;
  }

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
    // If user granted overlay permission in system Settings, detect on resume.
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

    // System-wide behavior (B): if enabled + granted, ensure overlay is running.
    if (_overlayEnabled && _overlayPermissionGranted) {
      await OverlayPlatform.startGlobalOverlay();
    }
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
      setState(() {
        _overlayEnabled = false;
      });
      await prefs.setLiveOverlayEnabled(false);
      await OverlayPlatform.stopGlobalOverlay();
      return;
    }

    // Enabling: explicit user action + permission flow.
    setState(() {
      _overlayEnabled = true;
    });
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
        title: Text(_trOr(l10n, 'live_overlay_permission_title', 'Allow overlay permission')),
        content: Text(
          _trOr(
            l10n,
            'live_overlay_permission_body',
            'To show the floating voice/message controls above other apps, Android requires an “Appear on top” permission. You can enable it in system settings.',
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

    if (proceed != true) {
      // Keep enabled but inactive until permission is granted (requirement).
      return;
    }

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
    final input = _quickInput.text;

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
    final l10n = context.l10n;
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    final themeState = ref.watch(themeControllerProvider);
    final localeState = ref.watch(localeControllerProvider);

    final currentLangCode = localeState.locale.languageCode;
    final supportedCodes = LocaleController.supportedLanguageCodes;

    final titleStyle = textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
    );

    final hintStyle = textTheme.bodySmall?.copyWith(
      color: cs.onSurface.withOpacity(0.72),
      fontWeight: FontWeight.w600,
    );

    final cardInnerFill = cs.onSurface.withOpacity(theme.brightness == Brightness.dark ? 0.08 : 0.04);
    final cardInnerStroke = cs.outlineVariant.withOpacity(theme.brightness == Brightness.dark ? 0.35 : 0.75);

    final overlayStatusText = !_overlayEnabled
        ? _trOr(l10n, 'live_overlay_status_off', 'Overlay: Off')
        : (_overlayPermissionGranted
            ? _trOr(l10n, 'live_overlay_status_on', 'Overlay: On')
            : _trOr(l10n, 'live_overlay_status_needs_permission', 'Overlay: Permission required'));

    final premium = ref.watch(isPremiumProvider).value ?? false;
    final customQuick = ref.watch(inAppCustomQuickMessagesProvider);

    return GlassScaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16),
              children: [
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.themeTitle, style: titleStyle),
                        const SizedBox(height: 8),
                        SegmentedButton<ThemeMode>(
                          segments: [
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text(l10n.themeSystem),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text(l10n.themeLight),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text(l10n.themeDark),
                            ),
                          ],
                          selected: {themeState.mode},
                          onSelectionChanged: (selectedModes) async {
                            final mode = selectedModes.first;
                            await ref.read(themeControllerProvider.notifier).setThemeMode(mode);
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(l10n.themeHint, style: hintStyle),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.languageTitle, style: titleStyle),
                        const SizedBox(height: 8),
                        Text(l10n.languageHint, style: hintStyle),
                        const SizedBox(height: 12),
                        DropdownButtonHideUnderline(
                          child: Container(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: cardInnerFill,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cardInnerStroke),
                            ),
                            child: DropdownButton<String>(
                              value: supportedCodes.contains(currentLangCode) ? currentLangCode : 'en',
                              dropdownColor: cs.surface,
                              iconEnabledColor: cs.onSurface.withOpacity(0.72),
                              style: textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                              isExpanded: true,
                              items: supportedCodes
                                  .map(
                                    (code) => DropdownMenuItem<String>(
                                      value: code,
                                      child: Directionality(
                                        textDirection: _languageTextDirection(code),
                                        child: Text(_languageDisplayName(code)),
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (code) async {
                                if (code == null) return;
                                await ref.read(localeControllerProvider.notifier).setLocale(code);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.notificationsTitle, style: titleStyle),
                        const SizedBox(height: 8),
                        if (_loading)
                          LinearProgressIndicator(
                            color: cs.primary,
                            backgroundColor: cs.onSurface.withOpacity(0.10),
                            minHeight: 2,
                          )
                        else ...[
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeColor: cs.primary,
                            title: Text(
                              l10n.notificationsEnabledTitle,
                              style: textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              l10n.notificationsEnabledSubtitle,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.60),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            value: _enabled,
                            onChanged: (v) async {
                              setState(() => _enabled = v);
                              await _saveNotifications();

                              if (v) {
                                await NotificationService().showTestNotification();
                              }
                            },
                          ),
                          Divider(color: cs.onSurface.withOpacity(0.10)),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeColor: cs.primary,
                            title: Text(
                              l10n.notificationsMatchRemindersTitle,
                              style: textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              l10n.notificationsMatchRemindersSubtitle,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.60),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            value: _matchReminders,
                            onChanged: !_enabled
                                ? null
                                : (v) async {
                                    setState(() => _matchReminders = v);
                                    await _saveNotifications();
                                  },
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeColor: cs.primary,
                            title: Text(
                              l10n.notificationsMarketingTitle,
                              style: textTheme.bodyMedium?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              l10n.notificationsMarketingSubtitle,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.60),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            value: _marketing,
                            onChanged: !_enabled
                                ? null
                                : (v) async {
                                    setState(() => _marketing = v);
                                    await _saveNotifications();
                                  },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // LIVE OVERLAY (system-wide)
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.liveOverlayTitle, style: titleStyle),
                        const SizedBox(height: 8),
                        Text(l10n.liveOverlayHint, style: hintStyle),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: cs.onSurface.withOpacity(theme.brightness == Brightness.dark ? 0.06 : 0.04),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cs.onSurface.withOpacity(0.10)),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _overlayEnabled
                                    ? (_overlayPermissionGranted ? Icons.check_circle_outline : Icons.warning_amber_rounded)
                                    : Icons.info_outline,
                                size: 18,
                                color: _overlayEnabled
                                    ? (_overlayPermissionGranted ? const Color(0xFF22C55E) : const Color(0xFFF59E0B))
                                    : cs.onSurface.withOpacity(0.65),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  overlayStatusText,
                                  style: textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.70),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_overlayEnabled && !_overlayPermissionGranted)
                                TextButton(
                                  onPressed: () async {
                                    await OverlayPlatform.requestOverlayPermission();
                                  },
                                  child: Text(_trOr(l10n, 'live_overlay_grant_permission', 'Grant')),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          activeColor: cs.primary,
                          title: Text(
                            l10n.liveOverlaySwitchTitle,
                            style: textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          subtitle: Text(
                            l10n.liveOverlaySwitchSubtitle,
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.60),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          value: _overlayEnabled,
                          onChanged: (v) async {
                            await _setOverlayEnabled(v);
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // QUICK MESSAGES (Premium)
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _trOr(l10n, 'quick_messages_title', 'Quick messages'),
                                style: titleStyle,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: premium ? const Color(0xFF22C55E).withOpacity(0.14) : cs.onSurface.withOpacity(0.06),
                                border: Border.all(
                                  color: premium ? const Color(0xFF22C55E).withOpacity(0.35) : cs.onSurface.withOpacity(0.14),
                                ),
                              ),
                              child: Text(
                                premium ? _trOr(l10n, 'common_premium', 'PREMIUM') : _trOr(l10n, 'common_locked', 'LOCKED'),
                                style: TextStyle(
                                  color: premium ? const Color(0xFF22C55E) : cs.onSurface.withOpacity(0.60),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _trOr(
                            l10n,
                            'quick_messages_hint',
                            'Defaults are included. Premium users can add up to 15 custom quick messages (max 15 chars). Links and mentions are not allowed.',
                          ),
                          style: hintStyle,
                        ),
                        const SizedBox(height: 10),

                        if (!premium) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.onSurface.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cs.onSurface.withOpacity(0.10)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.lock_outline, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _trOr(
                                      l10n,
                                      'quick_messages_premium_required',
                                      'Premium required to create custom quick messages.',
                                    ),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: cs.onSurface.withOpacity(0.75),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        behavior: SnackBarBehavior.floating,
                                        content: Text(
                                          _trOr(
                                            l10n,
                                            'quick_messages_upgrade_soon',
                                            'Upgrade flow not implemented yet. Set users/{uid}.isPremium=true in Firestore to test.',
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  child: Text(_trOr(l10n, 'common_upgrade', 'Upgrade')),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          if (customQuick.isEmpty)
                            Text(
                              _trOr(l10n, 'quick_messages_none_yet', 'No custom messages yet. Add one below.'),
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.60),
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          else
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: customQuick.length,
                              onReorder: (oldIndex, newIndex) async {
                                // ReorderableListView semantics: newIndex is "after removal"
                                if (newIndex > oldIndex) newIndex -= 1;
                                try {
                                  await ref.read(quickMessagesControllerProvider).reorderCustom(oldIndex, newIndex);
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      behavior: SnackBarBehavior.floating,
                                      content: Text(e.toString().replaceFirst('Exception: ', '')),
                                    ),
                                  );
                                }
                              },
                              itemBuilder: (ctx, i) {
                                final msg = customQuick[i];
                                return Container(
                                  key: ValueKey('custom_quick_$i:$msg'),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: cs.onSurface.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: cs.onSurface.withOpacity(0.10)),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.drag_handle),
                                    title: Text(
                                      msg,
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      tooltip: _trOr(l10n, 'common_delete', 'Delete'),
                                      onPressed: () => _deleteCustomQuickMessage(i),
                                      icon: Icon(Icons.delete_outline, color: cs.error),
                                    ),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _quickInput,
                                  maxLength: QuickMessagePolicy.maxChars,
                                  decoration: InputDecoration(
                                    counterText: '',
                                    filled: true,
                                    fillColor: cs.onSurface.withOpacity(0.04),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                    hintText: _trOr(l10n, 'quick_messages_add_hint', 'Add custom message…'),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton(
                                onPressed: _savingQuick ? null : _addCustomQuickMessage,
                                child: _savingQuick
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Text(_trOr(l10n, 'common_add', 'Add')),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // APP INFO
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.appInfoTitle, style: titleStyle),
                        const SizedBox(height: 8),
                        Text(
                          'eSportlyic powered by Kaida',
                          style: textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
