import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../persistence/prefs_service.dart';

/// App-level theme state
class ThemeState {
  final ThemeMode mode;

  const ThemeState({required this.mode});

  ThemeState copyWith({ThemeMode? mode}) {
    return ThemeState(mode: mode ?? this.mode);
  }
}

/// Riverpod controller for theme management
final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeState>(ThemeController.new);

class ThemeController extends Notifier<ThemeState> {
  static const _storageKeyLight = 'light';
  static const _storageKeyDark = 'dark';

  @override
  ThemeState build() {
    final prefs = ref.watch(prefsServiceProvider);
    final saved = prefs.getThemeMode();

    final ThemeMode initialMode = switch (saved) {
      _storageKeyDark => ThemeMode.dark,
      _storageKeyLight => ThemeMode.light,
      _ => ThemeMode.light,
    };

    return ThemeState(mode: initialMode);
  }

  /// Explicitly set theme mode and persist
  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    final value = mode == ThemeMode.dark ? _storageKeyDark : _storageKeyLight;
    await ref.read(prefsServiceProvider).setThemeMode(value);
  }

  /// Toggle between light and dark mode
  Future<void> toggleTheme() async {
    final next =
        state.mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setThemeMode(next);
  }

  bool get isDark => state.mode == ThemeMode.dark;
  bool get isLight => state.mode == ThemeMode.light;
}
