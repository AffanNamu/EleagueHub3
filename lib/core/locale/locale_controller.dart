import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persistence/prefs_service.dart';

/// App-level locale state
class LocaleState {
  final Locale locale;

  const LocaleState({required this.locale});

  LocaleState copyWith({Locale? locale}) {
    return LocaleState(locale: locale ?? this.locale);
  }
}

/// Riverpod controller for locale management
final localeControllerProvider =
    NotifierProvider<LocaleController, LocaleState>(
        LocaleController.new);

class LocaleController extends Notifier<LocaleState> {
  // Supported languages
  static const List<String> _supportedLanguageCodes = [
    'en', // English
    'pt', // Portuguese
    'id', // Indonesian
    'tr', // Turkish
    'ar', // Arabic
    'es', // Spanish
    'ja', // Japanese
    'fr', // French
    'sw', // Swahili
  ];

  static const Map<String, String> languageNames = {
    'en': 'English',
    'pt': 'Portuguese',
    'id': 'Indonesian',
    'tr': 'Turkish',
    'ar': 'Arabic',
    'es': 'Spanish',
    'ja': 'Japanese',
    'fr': 'French',
    'sw': 'Swahili',
  };

  static List<Locale> get supportedLocales => _supportedLanguageCodes
      .map((code) => Locale(code))
      .toList();

  @override
  LocaleState build() {
    final prefs = ref.watch(prefsServiceProvider);
    final saved = prefs.getLocaleCode();

    String langCode;

    if (saved != null &&
        _supportedLanguageCodes.contains(saved)) {
      langCode = saved;
    } else {
      final systemLocale =
          WidgetsBinding.instance.platformDispatcher.locale;
      final sysLang = systemLocale.languageCode;
      if (_supportedLanguageCodes.contains(sysLang)) {
        langCode = sysLang;
      } else {
        langCode = 'en';
      }
    }

    return LocaleState(locale: Locale(langCode));
  }

  /// Explicitly set locale and persist
  Future<void> setLocale(String languageCode) async {
    if (!_supportedLanguageCodes.contains(languageCode)) {
      languageCode = 'en';
    }
    state = state.copyWith(locale: Locale(languageCode));
    await ref.read(prefsServiceProvider).setLocaleCode(languageCode);
  }

  /// Convenience getter
  String get currentCode => state.locale.languageCode;
}
