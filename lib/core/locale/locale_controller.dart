import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persistence/prefs_service.dart';
import 'app_localizations.dart';

class LocaleState {
  final Locale locale;
  final TextDirection direction;

  const LocaleState({
    required this.locale,
    required this.direction,
  });

  LocaleState copyWith({
    Locale? locale,
    TextDirection? direction,
  }) {
    return LocaleState(
      locale: locale ?? this.locale,
      direction: direction ?? this.direction,
    );
  }

  bool get isRtl => direction == TextDirection.rtl;
}

final localeControllerProvider = NotifierProvider<LocaleController, LocaleState>(LocaleController.new);

class LocaleController extends Notifier<LocaleState> {
  static List<String> get supportedLanguageCodes => AppLocalizations.supportedLanguageCodes;

  @Deprecated('Use AppLocalizations.languageName(code) for user-facing language names.')
  static const Map<String, String> languageNames = {
    'en': 'English',
    'fr': 'French',
    'ru': 'Russian',
    'es': 'Spanish',
    'sw': 'Swahili',
    'ar': 'Arabic',
    'he': 'Hebrew',
    'ja': 'Japanese',
    'ko': 'Korean',
    'pt': 'Portuguese',
    'id': 'Indonesian',
    'tr': 'Turkish',
  };

  static List<Locale> get supportedLocales => AppLocalizations.supportedLocales;

  static const Set<String> _latinAmericaSpanishCountries = <String>{
    'MX',
    'AR',
    'CO',
    'CL',
    'PE',
    'VE',
    'EC',
    'GT',
    'CU',
    'BO',
    'DO',
    'HN',
    'PY',
    'SV',
    'NI',
    'CR',
    'PA',
    'UY',
    'PR',
  };

  static const Map<String, String> _countryToLanguageFallback = <String, String>{
    'NG': 'en',
    'CM': 'fr',
    'FR': 'fr',
    'RU': 'ru',
    'SA': 'ar',
    'IL': 'he',
    'KE': 'sw',
    'TZ': 'sw',
    'ES': 'es',
    'JP': 'ja',
    'KR': 'ko',
    'PT': 'pt',
    'BR': 'pt',
    'ID': 'id',
    'TR': 'tr',
  };

  @override
  LocaleState build() {
    final prefs = ref.watch(prefsServiceProvider);

    final savedCode = prefs.getLocaleCode();
    final manualOverride = prefs.getLocaleManualOverride();

    String resolvedCode;

    if (manualOverride && savedCode != null && supportedLanguageCodes.contains(savedCode)) {
      resolvedCode = savedCode;
    } else {
      resolvedCode = _resolveFromDeviceLocale(
        WidgetsBinding.instance.platformDispatcher.locales,
      );
    }

    final locale = Locale(resolvedCode);
    final direction =
        AppLocalizations.rtlLanguageCodes.contains(resolvedCode) ? TextDirection.rtl : TextDirection.ltr;

    return LocaleState(
      locale: locale,
      direction: direction,
    );
  }

  String _resolveFromDeviceLocale(List<Locale> systemLocales) {
    if (systemLocales.isEmpty) return 'en';

    for (final loc in systemLocales) {
      final lang = loc.languageCode;
      if (supportedLanguageCodes.contains(lang)) return lang;
    }

    final primary = systemLocales.first;
    final cc = (primary.countryCode ?? '').toUpperCase();

    if (_latinAmericaSpanishCountries.contains(cc)) return 'es';

    final mapped = _countryToLanguageFallback[cc];
    if (mapped != null && supportedLanguageCodes.contains(mapped)) {
      return mapped;
    }

    return 'en';
  }

  Future<void> setLocale(String languageCode) async {
    if (!supportedLanguageCodes.contains(languageCode)) {
      languageCode = 'en';
    }

    final direction =
        AppLocalizations.rtlLanguageCodes.contains(languageCode) ? TextDirection.rtl : TextDirection.ltr;

    state = state.copyWith(
      locale: Locale(languageCode),
      direction: direction,
    );

    final prefs = ref.read(prefsServiceProvider);
    await prefs.setLocaleCode(languageCode);
    await prefs.setLocaleManualOverride(true);
  }

  String get currentCode => state.locale.languageCode;
}
