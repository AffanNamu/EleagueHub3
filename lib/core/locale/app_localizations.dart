import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_localizations_1.dart';
import 'app_localizations_2.dart';
import 'app_localizations_3.dart';
import 'app_localizations_4.dart';
import 'app_localizations_5.dart';
import 'app_localizations_6.dart';
import 'app_localizations_7.dart';
import 'app_localizations_8.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static const Set<String> rtlLanguageCodes = <String>{
    'ar',
    'he',
  };

  static final Map<String, Map<String, String>> _strings = _buildStrings();

  static Map<String, Map<String, String>> _buildStrings() {
    final result = <String, Map<String, String>>{};

    void mergePart(Map<dynamic, dynamic> part) {
      for (final entry in part.entries) {
        final lang = (entry.key ?? '').toString().trim();
        if (lang.isEmpty) continue;

        final langMap = result.putIfAbsent(lang, () => <String, String>{});

        final rawStrings = entry.value;
        if (rawStrings is Map) {
          for (final e in rawStrings.entries) {
            final k = (e.key ?? '').toString().trim();
            if (k.isEmpty) continue;

            final v = e.value;
            if (v == null) continue;

            langMap[k] = v.toString();
          }
        }
      }
    }

    mergePart(appLocalizationsPart1);
    mergePart(appLocalizationsPart2);
    mergePart(appLocalizationsPart3);
    mergePart(appLocalizationsPart4);
    mergePart(appLocalizationsPart5);
    mergePart(appLocalizationsPart6);
    mergePart(appLocalizationsPart7);
    mergePart(appLocalizationsPart8);

    final frozen = <String, Map<String, String>>{};
    for (final entry in result.entries) {
      frozen[entry.key] = Map.unmodifiable(entry.value);
    }
    return Map.unmodifiable(frozen);
  }

  static List<String> get supportedLanguageCodes => _strings.keys.toList(growable: false);

  static List<Locale> get supportedLocales =>
      supportedLanguageCodes.map((code) => Locale(code)).toList(growable: false);

  static AppLocalizations of(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l10n != null) return l10n;

    Locale fallbackLocale;
    try {
      fallbackLocale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    } catch (_) {
      fallbackLocale = const Locale('en');
    }

    final code = _strings.containsKey(fallbackLocale.languageCode) ? fallbackLocale.languageCode : 'en';
    return AppLocalizations(Locale(code));
  }

  TextDirection get textDirection =>
      rtlLanguageCodes.contains(locale.languageCode) ? TextDirection.rtl : TextDirection.ltr;

  String tr(String key) {
    final lang = locale.languageCode;
    final current = _strings[lang];
    if (current != null && current.containsKey(key)) {
      return current[key]!;
    }
    final en = _strings['en'];
    if (en != null && en.containsKey(key)) {
      return en[key]!;
    }
    return key;
  }

  String get appName => tr('app_name');

  String get settingsTitle => tr('settings_title');

  String get themeTitle => tr('theme_title');
  String get themeSystem => tr('theme_system');
  String get themeLight => tr('theme_light');
  String get themeDark => tr('theme_dark');
  String get themeHint => tr('theme_hint');

  String get languageTitle => tr('language_title');
  String get languageHint => tr('language_hint');

  String languageName(String code) => tr('language_name_$code');

  String get notificationsTitle => tr('notifications_title');
  String get notificationsEnabledTitle => tr('notifications_enabled_title');
  String get notificationsEnabledSubtitle => tr('notifications_enabled_subtitle');
  String get notificationsMatchRemindersTitle => tr('notifications_match_reminders_title');
  String get notificationsMatchRemindersSubtitle => tr('notifications_match_reminders_subtitle');
  String get notificationsMarketingTitle => tr('notifications_marketing_title');
  String get notificationsMarketingSubtitle => tr('notifications_marketing_subtitle');

  String get liveOverlayTitle => tr('live_overlay_title');
  String get liveOverlayHint => tr('live_overlay_hint');
  String get liveOverlaySwitchTitle => tr('live_overlay_switch_title');
  String get liveOverlaySwitchSubtitle => tr('live_overlay_switch_subtitle');

  String get appInfoTitle => tr('app_info_title');
  String get appInfoLine1 => tr('app_info_line1');
  String get appInfoLine2 => tr('app_info_line2');

  String get settingsGroupAppPreferences => tr('settings_group_app_preferences');
  String get settingsGroupAccountSecurity => tr('settings_group_account_security');
  String get settingsItemNotifications => tr('settings_item_notifications');
  String get settingsItemNotificationsSubtitle => tr('settings_item_notifications_subtitle');
  String get settingsItemAppearance => tr('settings_item_appearance');
  String get settingsItemAppearanceSubtitle => tr('settings_item_appearance_subtitle');
  String get settingsItemLanguage => tr('settings_item_language');
  String get settingsItemPrivacy => tr('settings_item_privacy');
  String get settingsItemPrivacySubtitle => tr('settings_item_privacy_subtitle');
  String get settingsItemCloudSync => tr('settings_item_cloud_sync');
  String get settingsItemCloudSyncSubtitle => tr('settings_item_cloud_sync_subtitle');
  String get settingsItemDeleteAccount => tr('settings_item_delete_account');
  String get settingsItemDeleteAccountSubtitle => tr('settings_item_delete_account_subtitle');

  String get settingsProfileName => tr('settings_profile_name');
  String get settingsProfileEmail => tr('settings_profile_email');

  String get settingsFooterVersion => tr('settings_footer_version');

  String get authBootstrapLoading => tr('auth_bootstrap_loading');

  String get authLoginBrand => tr('auth_login_brand');
  String get authLoginSubtitleSignIn => tr('auth_login_subtitle_signin');
  String get authLoginSubtitleRegister => tr('auth_login_subtitle_register');
  String get authLoginContinueWithGoogle => tr('auth_login_continue_google');
  String get authLoginOr => tr('auth_login_or');
  String get authLoginEmailLabel => tr('auth_login_email_label');
  String get authLoginPasswordLabel => tr('auth_login_password_label');
  String get authLoginConfirmPasswordLabel => tr('auth_login_confirm_password_label');
  String get authLoginCreateAccount => tr('auth_login_create_account');
  String get authLoginSignIn => tr('auth_login_sign_in');
  String get authLoginToggleToSignIn => tr('auth_login_toggle_to_sign_in');
  String get authLoginToggleToRegister => tr('auth_login_toggle_to_register');

  String get onboardingTitle => tr('onboarding_title');
  String get onboardingHeader => tr('onboarding_header');
  String get onboardingDescription => tr('onboarding_description');
  String get onboardingTeamNameLabel => tr('onboarding_team_name_label');
  String get onboardingFavoriteGameLabel => tr('onboarding_favorite_game_label');
  String get onboardingExperienceLevelLabel => tr('onboarding_experience_level_label');
  String get onboardingRegionLabel => tr('onboarding_region_label');
  String get onboardingContinue => tr('onboarding_continue');

  String get homeTabHome => tr('home_tab_home');
  String get homeTabLeagues => tr('home_tab_leagues');
  String get homeTabLive => tr('home_tab_live');
  String get homeTabMarketplace => tr('home_tab_marketplace');
  String get homeTabProfile => tr('home_tab_profile');
  String get homeSettingsTooltip => tr('home_settings_tooltip');

  String get homeWelcomeBack => tr('home_welcome_back');
  String get homeMvpDescription => tr('home_mvp_description');
  String get homeAnnouncementsTitle => tr('home_announcements_title');

  String get homeAnnouncement1Title => tr('home_announcement_1_title');
  String get homeAnnouncement1Message => tr('home_announcement_1_message');
  String get homeAnnouncement1Time => tr('home_announcement_1_time');

  String get homeAnnouncement2Title => tr('home_announcement_2_title');
  String get homeAnnouncement2Message => tr('home_announcement_2_message');
  String get homeAnnouncement2Time => tr('home_announcement_2_time');

  String get homeAnnouncement3Title => tr('home_announcement_3_title');
  String get homeAnnouncement3Message => tr('home_announcement_3_message');
  String get homeAnnouncement3Time => tr('home_announcement_3_time');

  String get homeQuickCreateLeagueTitle => tr('home_quick_create_league_title');
  String get homeQuickCreateLeagueSubtitle => tr('home_quick_create_league_subtitle');
  String get homeQuickJoinLiveTitle => tr('home_quick_join_live_title');
  String get homeQuickJoinLiveSubtitle => tr('home_quick_join_live_subtitle');

  String get errorEmailPasswordRequired => tr('error_email_password_required');
  String get errorPasswordsDoNotMatch => tr('error_passwords_do_not_match');
  String get errorPasswordMinLength => tr('error_password_min_length');
  String get errorTeamNameRequired => tr('error_team_name_required');
  String get errorFailedOnboardingPrefix => tr('error_failed_onboarding_prefix');
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocalizations._strings.containsKey(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    final resolved =
        AppLocalizations._strings.containsKey(locale.languageCode) ? locale : const Locale('en');
    return SynchronousFuture<AppLocalizations>(AppLocalizations(resolved));
  }

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppLocalizations> old) => false;
}

extension BuildContextAppL10n on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
