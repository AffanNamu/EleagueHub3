import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/services/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _enabled = true;
  bool _marketing = false;
  bool _matchReminders = true;

  bool _overlayEnabled = true;

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
    _load();
  }

  Future<void> _load() async {
    final prefs = ref.read(prefsServiceProvider);
    final map = await prefs.loadNotificationPrefs();
    final overlay = prefs.liveOverlayEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = map['enabled'] ?? true;
      _marketing = map['marketing'] ?? false;
      _matchReminders = map['matchReminders'] ?? true;
      _overlayEnabled = overlay;
      _loading = false;
    });
  }

  Future<void> _saveNotifications() async {
    final prefs = ref.read(prefsServiceProvider);
    await prefs.saveNotificationPrefs(
      enabled: _enabled,
      marketing: _marketing,
      matchReminders: _matchReminders,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final themeState = ref.watch(themeControllerProvider);
    final localeState = ref.watch(localeControllerProvider);
    final textTheme = Theme.of(context).textTheme;

    final currentLangCode = localeState.locale.languageCode;
    final supportedCodes = LocaleController.supportedLanguageCodes;

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
                        Text(
                          l10n.themeTitle,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
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
                        Text(
                          l10n.themeHint,
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
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
                        Text(
                          l10n.languageTitle,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.languageHint,
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonHideUnderline(
                          child: Container(
                            padding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white24,
                              ),
                            ),
                            child: DropdownButton<String>(
                              value: supportedCodes.contains(currentLangCode) ? currentLangCode : 'en',
                              dropdownColor: const Color(0xFF000428),
                              style: const TextStyle(
                                color: Colors.cyanAccent,
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
                        Text(
                          l10n.notificationsTitle,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_loading)
                          const LinearProgressIndicator(
                            color: Colors.cyanAccent,
                            minHeight: 2,
                          )
                        else ...[
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeColor: Colors.cyanAccent,
                            title: Text(
                              l10n.notificationsEnabledTitle,
                              style: const TextStyle(
                                color: Colors.white,
                              ),
                            ),
                            subtitle: Text(
                              l10n.notificationsEnabledSubtitle,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
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
                          const Divider(
                            color: Colors.white10,
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            activeColor: Colors.cyanAccent,
                            title: Text(
                              l10n.notificationsMatchRemindersTitle,
                              style: const TextStyle(
                                color: Colors.white,
                              ),
                            ),
                            subtitle: Text(
                              l10n.notificationsMatchRemindersSubtitle,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
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
                            activeColor: Colors.cyanAccent,
                            title: Text(
                              l10n.notificationsMarketingTitle,
                              style: const TextStyle(
                                color: Colors.white,
                              ),
                            ),
                            subtitle: Text(
                              l10n.notificationsMarketingSubtitle,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
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
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.liveOverlayTitle,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.liveOverlayHint,
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.cyanAccent,
                          title: Text(
                            l10n.liveOverlaySwitchTitle,
                            style: const TextStyle(
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            l10n.liveOverlaySwitchSubtitle,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                          value: _overlayEnabled,
                          onChanged: (v) async {
                            setState(() => _overlayEnabled = v);
                            final prefs = ref.read(prefsServiceProvider);
                            await prefs.setLiveOverlayEnabled(v);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // APP INFO (custom text requested)
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.appInfoTitle,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'eSportlyic powered by Kaida',
                          style: TextStyle(
                            color: Colors.white,
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
