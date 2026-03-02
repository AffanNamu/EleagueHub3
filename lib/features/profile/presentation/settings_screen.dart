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
  ConsumerState<SettingsScreen> createState() =>
      _SettingsScreenState();
}

class _SettingsScreenState
    extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _enabled = true;
  bool _marketing = false;
  bool _matchReminders = true;

  bool _overlayEnabled = false;
  bool _overlayPermissionGranted = false;

  final TextEditingController _quickInput =
      TextEditingController();

  bool _savingQuick = false;

  static const Map<String, String>
      _languageAutonyms = {
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

  static bool _isRtlLangCode(String code) =>
      code == 'ar' || code == 'he';

  String _languageDisplayName(String code) =>
      _languageAutonyms[code] ??
      code.toUpperCase();

  TextDirection _languageTextDirection(
          String code) =>
      _isRtlLangCode(code)
          ? TextDirection.rtl
          : TextDirection.ltr;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance
        .removeObserver(this);
    _quickInput.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(
      AppLifecycleState state) {
    if (state ==
        AppLifecycleState.resumed) {
      unawaited(
          _refreshOverlayPermissionAndMaybeStart());
    }
  }

  Future<void> _load() async {
    final prefs =
        ref.read(prefsServiceProvider);

    final map =
        await prefs.loadNotificationPrefs();

    final overlay =
        prefs.liveOverlayEnabled();

    final granted =
        await OverlayPlatform
            .isOverlayPermissionGranted();

    if (!mounted) return;

    setState(() {
      _enabled =
          map['enabled'] ?? true;
      _marketing =
          map['marketing'] ?? false;
      _matchReminders =
          map['matchReminders'] ??
              true;
      _overlayEnabled = overlay;
      _overlayPermissionGranted =
          granted;
      _loading = false;
    });

    if (_overlayEnabled &&
        _overlayPermissionGranted) {
      await OverlayPlatform
          .startGlobalOverlay();
    }
  }

  Future<void> _saveNotifications() async {
    final prefs =
        ref.read(prefsServiceProvider);

    await prefs.saveNotificationPrefs(
      enabled: _enabled,
      marketing: _marketing,
      matchReminders:
          _matchReminders,
    );
  }

  Future<void>
      _refreshOverlayPermissionAndMaybeStart() async {
    final granted =
        await OverlayPlatform
            .isOverlayPermissionGranted();

    if (!mounted) return;

    setState(() =>
        _overlayPermissionGranted =
            granted);

    if (_overlayEnabled &&
        granted) {
      await OverlayPlatform
          .startGlobalOverlay();
    }
  }

  Future<void> _setOverlayEnabled(
      bool enabled) async {
    final prefs =
        ref.read(prefsServiceProvider);

    if (!enabled) {
      setState(() =>
          _overlayEnabled = false);

      await prefs
          .setLiveOverlayEnabled(false);

      await OverlayPlatform
          .stopGlobalOverlay();
      return;
    }

    setState(() =>
        _overlayEnabled = true);

    await prefs
        .setLiveOverlayEnabled(true);

    final granted =
        await OverlayPlatform
            .isOverlayPermissionGranted();

    if (!mounted) return;

    setState(() =>
        _overlayPermissionGranted =
            granted);

    if (granted) {
      await OverlayPlatform
          .startGlobalOverlay();
      return;
    }

    await OverlayPlatform
        .requestOverlayPermission();
  }

  Future<void>
      _addCustomQuickMessage() async {
    if (_savingQuick) return;

    final input =
        _quickInput.text;

    setState(() =>
        _savingQuick = true);

    try {
      await ref
          .read(
              quickMessagesControllerProvider)
          .addCustomMessage(input);

      _quickInput.clear();
    } finally {
      if (mounted) {
        setState(() =>
            _savingQuick = false);
      }
    }
  }

  Future<void>
      _deleteCustomQuickMessage(
          int index) async {
    await ref
        .read(
            quickMessagesControllerProvider)
        .deleteCustomMessageAt(index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n =
        context.l10n;
    final theme =
        Theme.of(context);
    final cs =
        theme.colorScheme;
    final onSurface =
        cs.onSurface;

    final themeState =
        ref.watch(
            themeControllerProvider);

    final localeState =
        ref.watch(
            localeControllerProvider);

    final currentLangCode =
        localeState
            .locale
            .languageCode;

    final supportedCodes =
        LocaleController
            .supportedLanguageCodes;

    final premium =
        ref.watch(
                isPremiumProvider)
            .value ??
            false;

    final customQuick =
        ref.watch(
            inAppCustomQuickMessagesProvider);

    return GlassScaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor:
            Colors.transparent,
        title: Text(
          l10n.settingsTitle,
          style: theme
              .textTheme
              .titleLarge
              ?.copyWith(
            fontWeight:
                FontWeight.w900,
            letterSpacing:
                -0.3,
            color: onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          physics:
              const BouncingScrollPhysics(
                  parent:
                      AlwaysScrollableScrollPhysics()),
          padding:
              const EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  120),
          children: [
            // ── Theme Section ──
            _SectionLabel(
                icon:
                    Icons.palette_rounded,
                label:
                    l10n.themeTitle),
            const SizedBox(
                height: 8),
            Glass(
              borderRadius: 20,
              padding:
                  const EdgeInsets.all(
                      16),
              child: Row(
                children: [
                  for (final mode
                      in ThemeMode
                          .values) ...[
                    if (mode !=
                        ThemeMode
                            .values
                            .first)
                      const SizedBox(
                          width:
                              8),
                    Expanded(
                      child:
                          _ThemeModeCard(
                        icon:
                            _themeModeIcon(
                                mode),
                        label:
                            _themeModeLabel(
                                mode,
                                l10n),
                        selected:
                            themeState
                                    .mode ==
                                mode,
                        onTap: () async {
                          await ref
                              .read(
                                  themeControllerProvider
                                      .notifier)
                              .setThemeMode(
                                  mode);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),             const SizedBox(height: 24),

            // ── Language Section ──
            _SectionLabel(
              icon: Icons.language_rounded,
              label: l10n.languageTitle,
            ),
            const SizedBox(height: 8),
            Glass(
              borderRadius: 20,
              padding: const EdgeInsets.all(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  _showLanguagePicker(
                    context,
                    supportedCodes,
                    currentLangCode,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color:
                        onSurface.withOpacity(0.05),
                    borderRadius:
                        BorderRadius.circular(14),
                    border: Border.all(
                      color: onSurface
                          .withOpacity(0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.translate_rounded,
                          color: cs.primary,
                          size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Directionality(
                          textDirection:
                              _languageTextDirection(
                                  currentLangCode),
                          child: Text(
                            _languageDisplayName(
                                currentLangCode),
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.w800,
                              fontSize: 14,
                              color: onSurface,
                            ),
                          ),
                        ),
                      ),
                      Icon(
                        Icons
                            .chevron_right_rounded,
                        color: onSurface
                            .withOpacity(0.35),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Notifications Section ──
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
                      child:
                          CircularProgressIndicator(
                        color: cs.primary,
                        strokeWidth: 2,
                      ),
                    )
                  : Column(
                      children: [
                        _SettingsToggle(
                          icon: Icons
                              .notifications_active_rounded,
                          title: l10n
                              .notificationsEnabledTitle,
                          subtitle: l10n
                              .notificationsEnabledSubtitle,
                          value: _enabled,
                          onChanged: (v) async {
                            setState(() =>
                                _enabled = v);
                            await _saveNotifications();
                            if (v) {
                              await NotificationService()
                                  .showTestNotification();
                            }
                          },
                        ),
                        Divider(
                            color: onSurface
                                .withOpacity(0.08),
                            height: 1),
                        _SettingsToggle(
                          icon:
                              Icons.alarm_rounded,
                          title: l10n
                              .notificationsMatchRemindersTitle,
                          subtitle: l10n
                              .notificationsMatchRemindersSubtitle,
                          value: _matchReminders,
                          enabled: _enabled,
                          onChanged: (v) async {
                            setState(() =>
                                _matchReminders =
                                    v);
                            await _saveNotifications();
                          },
                        ),
                        Divider(
                            color: onSurface
                                .withOpacity(0.08),
                            height: 1),
                        _SettingsToggle(
                          icon:
                              Icons.campaign_rounded,
                          title: l10n
                              .notificationsMarketingTitle,
                          subtitle: l10n
                              .notificationsMarketingSubtitle,
                          value: _marketing,
                          enabled: _enabled,
                          onChanged: (v) async {
                            setState(() =>
                                _marketing = v);
                            await _saveNotifications();
                          },
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 24),

            // ── Quick Messages Section ──
            _SectionLabel(
              icon: Icons.chat_bubble_rounded,
              label: _trOr(
                  l10n,
                  'quick_messages_title',
                  'Quick Messages'),
            ),
            const SizedBox(height: 8),
            Glass(
              borderRadius: 20,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  if (!premium)
                    Text(
                      'Premium required to create custom quick messages.',
                      style: TextStyle(
                        color: onSurface
                            .withOpacity(0.60),
                        fontSize: 12,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    )
                  else ...[
                    if (customQuick
                        .isEmpty)
                      Text(
                        'No custom messages yet.',
                        style: TextStyle(
                          color: onSurface
                              .withOpacity(0.55),
                          fontSize: 12,
                        ),
                      )
                    else
                      ...customQuick
                          .asMap()
                          .entries
                          .map(
                        (e) =>
                            _QuickMessageTile(
                          message:
                              e.value,
                          onDelete: () =>
                              _deleteCustomQuickMessage(
                                  e.key),
                        ),
                      ),

                    const SizedBox(
                        height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller:
                                _quickInput,
                            maxLength:
                                QuickMessagePolicy
                                    .maxChars,
                            decoration:
                                const InputDecoration(
                              hintText:
                                  'Add custom message…',
                              counterText:
                                  '',
                            ),
                          ),
                        ),
                        const SizedBox(
                            width: 10),
                        ElevatedButton(
                          onPressed:
                              _savingQuick
                                  ? null
                                  : _addCustomQuickMessage,
                          child: _savingQuick
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth:
                                        2,
                                    color: Colors
                                        .white,
                                  ),
                                )
                              : const Icon(
                                  Icons
                                      .add_rounded),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _themeModeLabel(
      ThemeMode mode,
      AppLocalizations l10n) {
    switch (mode) {
      case ThemeMode.system:
        return l10n.themeSystem;
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return l10n.themeDark;
    }
  }

  IconData _themeModeIcon(
      ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return Icons
            .brightness_auto_rounded;
      case ThemeMode.light:
        return Icons
            .light_mode_rounded;
      case ThemeMode.dark:
        return Icons
            .dark_mode_rounded;
    }
  }

  void _showLanguagePicker(
    BuildContext context,
    List<String> codes,
    String current,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor:
          Colors.transparent,
      builder: (ctx) {
        final cs =
            Theme.of(ctx)
                .colorScheme;
        final onSurface =
            cs.onSurface;

        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(
                    12),
            child: Glass(
              borderRadius: 24,
              padding:
                  const EdgeInsets.all(
                      16),
              child: ListView(
                shrinkWrap: true,
                children: codes
                    .map(
                      (code) =>
                          ListTile(
                        title:
                            Directionality(
                          textDirection:
                              _languageTextDirection(
                                  code),
                          child: Text(
                            _languageDisplayName(
                                code),
                          ),
                        ),
                        trailing:
                            code ==
                                    current
                                ? Icon(
                                    Icons
                                        .check_circle_rounded,
                                    color: cs
                                        .primary,
                                  )
                                : null,
                        onTap: () async {
                          Navigator.of(
                                  ctx)
                              .pop();
                          await ref
                              .read(
                                  localeControllerProvider
                                      .notifier)
                              .setLocale(
                                  code);
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// Section Label
// ─────────────────────────────────────────────

class _SectionLabel
    extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(
      BuildContext context) {
    final cs =
        Theme.of(context)
            .colorScheme;
    final onSurface =
        cs.onSurface;

    return Row(
      children: [
        Icon(icon,
            size: 16,
            color: cs.primary
                .withOpacity(0.7)),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontWeight:
                FontWeight.w900,
            fontSize: 14,
            color: onSurface
                .withOpacity(0.75),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Theme Mode Card
// ─────────────────────────────────────────────

class _ThemeModeCard
    extends StatelessWidget {
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
  Widget build(
      BuildContext context) {
    final cs =
        Theme.of(context)
            .colorScheme;
    final onSurface =
        cs.onSurface;
    final color = selected
        ? cs.primary
        : onSurface
            .withOpacity(0.65);

    return InkWell(
      onTap: onTap,
      borderRadius:
          BorderRadius.circular(
              14),
      child: Container(
        padding:
            const EdgeInsets.symmetric(
                vertical: 14),
        decoration:
            BoxDecoration(
          borderRadius:
              BorderRadius.circular(
                  14),
          color: selected
              ? cs.primary
                  .withOpacity(0.12)
              : onSurface
                  .withOpacity(0.04),
          border: Border.all(
            color: selected
                ? cs.primary
                    .withOpacity(
                        0.35)
                : onSurface
                    .withOpacity(
                        0.10),
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: color,
                size: 22),
            const SizedBox(
                height: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight:
                    selected
                        ? FontWeight
                            .w900
                        : FontWeight
                            .w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Settings Toggle
// ─────────────────────────────────────────────

class _SettingsToggle
    extends StatelessWidget {
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
  final ValueChanged<bool>
      onChanged;
  final bool enabled;

  @override
  Widget build(
      BuildContext context) {
    final cs =
        Theme.of(context)
            .colorScheme;
    final onSurface =
        cs.onSurface;

    return Opacity(
      opacity:
          enabled ? 1 : 0.4,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
                vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration:
                  BoxDecoration(
                shape: BoxShape
                    .circle,
                color: cs.primary
                    .withOpacity(
                        0.10),
              ),
              child: Icon(icon,
                  color:
                      cs.primary,
                  size: 16),
            ),
            const SizedBox(
                width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    title,
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight
                              .w800,
                      fontSize:
                          13,
                      color:
                          onSurface,
                    ),
                  ),
                  const SizedBox(
                      height: 2),
                  Text(
                    subtitle,
                    style:
                        TextStyle(
                      color: onSurface
                          .withOpacity(
                              0.55),
                      fontSize:
                          11,
                      fontWeight:
                          FontWeight
                              .w600,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged:
                  enabled
                      ? onChanged
                      : null,
              activeColor:
                  cs.primary,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Quick Message Tile
// ─────────────────────────────────────────────

class _QuickMessageTile
    extends StatelessWidget {
  const _QuickMessageTile({
    required this.message,
    required this.onDelete,
  });

  final String message;
  final VoidCallback onDelete;

  @override
  Widget build(
      BuildContext context) {
    final onSurface =
        Theme.of(context)
            .colorScheme
            .onSurface;

    return Container(
      margin:
          const EdgeInsets.only(
              bottom: 6),
      padding:
          const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10),
      decoration:
          BoxDecoration(
        color: onSurface
            .withOpacity(0.04),
        borderRadius:
            BorderRadius.circular(
                12),
        border: Border.all(
            color: onSurface
                .withOpacity(
                    0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style:
                  TextStyle(
                fontWeight:
                    FontWeight.w800,
                fontSize: 13,
                color:
                    onSurface,
              ),
            ),
          ),
          InkWell(
            onTap: onDelete,
            borderRadius:
                BorderRadius
                    .circular(
                        8),
            child: const Padding(
              padding:
                  EdgeInsets.all(
                      4),
              child: Icon(
                Icons
                    .delete_outline_rounded,
                size: 18,
                color: Colors
                    .redAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

