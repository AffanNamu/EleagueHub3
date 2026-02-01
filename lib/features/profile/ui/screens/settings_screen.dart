import 'package:flutter/material.dart';
import 'dart:ui';

import '../../../../core/locale/app_localizations.dart';
import '../../../../core/locale/locale_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentCode = Localizations.localeOf(context).languageCode;
    final languageLabel =
        LocaleController.supportedLanguageCodes.contains(currentCode) ? l10n.languageName(currentCode) : l10n.languageName('en');

    return Scaffold(
      backgroundColor: const Color(0xFF4FC3F7),
      appBar: AppBar(
        title: Text(
          l10n.settingsTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildProfileSection(context),
            const SizedBox(height: 24),
            _buildSettingsGroup(context, l10n.settingsGroupAppPreferences, [
              _SettingItem(Icons.notifications_none, l10n.settingsItemNotifications, l10n.settingsItemNotificationsSubtitle),
              _SettingItem(Icons.dark_mode_outlined, l10n.settingsItemAppearance, l10n.settingsItemAppearanceSubtitle),
              _SettingItem(Icons.language, l10n.settingsItemLanguage, languageLabel),
            ]),
            const SizedBox(height: 24),
            _buildSettingsGroup(context, l10n.settingsGroupAccountSecurity, [
              _SettingItem(Icons.lock_outline, l10n.settingsItemPrivacy, l10n.settingsItemPrivacySubtitle),
              _SettingItem(Icons.sync, l10n.settingsItemCloudSync, l10n.settingsItemCloudSyncSubtitle),
              _SettingItem(
                Icons.delete_forever,
                l10n.settingsItemDeleteAccount,
                l10n.settingsItemDeleteAccountSubtitle,
                isDestructive: true,
              ),
            ]),
            const SizedBox(height: 40),
            Text(
              l10n.settingsFooterVersion,
              style: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    final l10n = context.l10n;

    return _buildGlassBox(
      child: Row(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.cyanAccent, width: 2),
              image: const DecorationImage(image: NetworkImage('https://via.placeholder.com/150')),
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsProfileName,
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Text(
                l10n.settingsProfileEmail,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          const Spacer(),
          IconButton(onPressed: () {}, icon: const Icon(Icons.edit, color: Colors.cyanAccent, size: 20)),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(BuildContext context, String title, List<_SettingItem> items) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 8, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
          ),
        ),
        _buildGlassBox(
          padding: EdgeInsets.zero,
          child: Column(
            children: items.map((item) {
              final isLast = items.indexOf(item) == items.length - 1;
              return Column(
                children: [
                  ListTile(
                    leading: Icon(item.icon, color: item.isDestructive ? Colors.redAccent : Colors.white70),
                    title: Text(
                      item.title,
                      style: TextStyle(color: item.isDestructive ? Colors.redAccent : Colors.white, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(item.subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
                    onTap: () {},
                  ),
                  if (!isLast)
                    Divider(
                      color: Colors.white.withOpacity(0.05),
                      height: 1,
                      indent: isRtl ? 0 : 50,
                      endIndent: isRtl ? 50 : 0,
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassBox({required Widget child, EdgeInsets padding = const EdgeInsets.all(20)}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SettingItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isDestructive;
  _SettingItem(this.icon, this.title, this.subtitle, {this.isDestructive = false});
}
