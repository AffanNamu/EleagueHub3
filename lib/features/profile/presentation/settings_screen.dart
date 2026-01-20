import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../core/services/notification_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() =>
      _SettingsScreenState();
}

class _SettingsScreenState
    extends ConsumerState<SettingsScreen> {
  bool _loading = true;
  bool _enabled = true;
  bool _marketing = false;
  bool _matchReminders = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = ref.read(prefsServiceProvider);
    final map = await prefs.loadNotificationPrefs();
    if (!mounted) return;
    setState(() {
      _enabled = map['enabled'] ?? true;
      _marketing = map['marketing'] ?? false;
      _matchReminders = map['matchReminders'] ?? true;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = ref.read(prefsServiceProvider);
    await prefs.saveNotificationPrefs(
      enabled: _enabled,
      marketing: _marketing,
      matchReminders: _matchReminders,
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeControllerProvider);
    final localeState = ref.watch(localeControllerProvider);
    final textTheme = Theme.of(context).textTheme;

    final currentLangCode = localeState.locale.languageCode;
    final langNames = LocaleController.languageNames;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                16,
              ),
              children: [
                // THEME CARD
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Theme',
                          style: textTheme.titleMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('System'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Sky Blue'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Deep Navy'),
                            ),
                          ],
                          selected: {themeState.mode},
                          onSelectionChanged:
                              (selectedModes) async {
                            final mode =
                                selectedModes.first;
                            await ref
                                .read(
                                  themeControllerProvider
                                      .notifier,
                                )
                                .setThemeMode(mode);
                          },
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Auto-detects system brightness on first launch. Your choice persists.',
                          style: textTheme.bodySmall
                              ?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // LANGUAGE CARD
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Language',
                          style: textTheme.titleMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Auto-detected from your device on first launch. You can change it manually here.',
                          style: textTheme.bodySmall
                              ?.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonHideUnderline(
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white
                                  .withOpacity(0.06),
                              borderRadius:
                                  BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white24,
                              ),
                            ),
                            child: DropdownButton<String>(
                              value: currentLangCode,
                              dropdownColor:
                                  const Color(0xFF000428),
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                              ),
                              isExpanded: true,
                              items: langNames.entries
                                  .map(
                                    (e) =>
                                        DropdownMenuItem<String>(
                                      value: e.key,
                                      child: Text(e.value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (code) async {
                                if (code == null) return;
                                await ref
                                    .read(
                                      localeControllerProvider
                                          .notifier,
                                    )
                                    .setLocale(code);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // NOTIFICATIONS CARD
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications',
                          style: textTheme.titleMedium
                              ?.copyWith(
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
                            contentPadding:
                                EdgeInsets.zero,
                            activeColor:
                                Colors.cyanAccent,
                            title: const Text(
                              'Enabled',
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                            subtitle: const Text(
                              'Turn all notifications on or off',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                            value: _enabled,
                            onChanged: (v) async {
                              setState(
                                  () => _enabled = v);
                              await _save();

                              // When enabling, show a test notification
                              if (v) {
                                await NotificationService()
                                    .showTestNotification();
                              }
                            },
                          ),
                          const Divider(
                            color: Colors.white10,
                          ),
                          SwitchListTile.adaptive(
                            contentPadding:
                                EdgeInsets.zero,
                            activeColor:
                                Colors.cyanAccent,
                            title: const Text(
                              'Match reminders',
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                            subtitle: const Text(
                              'Remind me before my matches',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                            value: _matchReminders,
                            onChanged: !_enabled
                                ? null
                                : (v) async {
                                    setState(() =>
                                        _matchReminders =
                                            v);
                                    await _save();
                                  },
                          ),
                          SwitchListTile.adaptive(
                            contentPadding:
                                EdgeInsets.zero,
                            activeColor:
                                Colors.cyanAccent,
                            title: const Text(
                              'Marketing',
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                            subtitle: const Text(
                              'Tips, news and occasional promotions',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                            value: _marketing,
                            onChanged: !_enabled
                                ? null
                                : (v) async {
                                    setState(() =>
                                        _marketing =
                                            v);
                                    await _save();
                                  },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // APP INFO CARD
                Glass(
                  borderRadius: 24,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'App info',
                          style: textTheme.titleMedium
                              ?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'EleagueHub • MVP skeleton',
                          style: TextStyle(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No backend connected. Offline mock data.',
                          style: textTheme.bodySmall
                              ?.copyWith(
                            color: Colors.white70,
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
