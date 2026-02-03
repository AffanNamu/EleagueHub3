import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';

class BatteryOptimizationGuide {
  static const _ch = MethodChannel('local_live');

  static Future<Map<String, dynamic>> _deviceInfo() async {
    if (!Platform.isAndroid) return {};
    final res = await _ch.invokeMethod('getDeviceInfo');
    if (res is Map) return res.cast<String, dynamic>();
    return {};
  }

  static Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod('openBatteryOptimizationSettings');
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod('requestIgnoreBatteryOptimizations');
  }

  static Future<void> openAppDetailsSettings() async {
    if (!Platform.isAndroid) return;
    await _ch.invokeMethod('openAppDetailsSettings');
  }

  static Future<void> show(BuildContext context) async {
    final l10n = context.l10n;

    final info = await _deviceInfo();
    final manufacturer = (info['manufacturer'] ?? '').toString().toLowerCase();
    final brand = (info['brand'] ?? '').toString().toLowerCase();
    final model = (info['model'] ?? '').toString();

    final vendor = (manufacturer.isNotEmpty ? manufacturer : brand);

    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final vendorLabel = vendor.isEmpty ? l10n.tr('battery_opt_android') : vendor.toUpperCase();
        final modelSuffix = model.isNotEmpty ? ' • $model' : '';

        return Padding(
          padding: EdgeInsets.only(
            left: 12,
            right: 12,
            bottom: MediaQuery.of(ctx).padding.bottom + 12,
            top: 12,
          ),
          child: Glass(
            borderRadius: 22,
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.tr('battery_opt_title'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.tr('battery_opt_device_prefix')}$vendorLabel$modelSuffix',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.tr('battery_opt_intro'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  _StepsBox(text: _stepsForVendor(l10n, vendor)),
                  const SizedBox(height: 12),
                  Text(
                    l10n.tr('battery_opt_quick_buttons'),
                    style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: requestIgnoreBatteryOptimizations,
                    icon: const Icon(Icons.battery_saver),
                    label: Text(l10n.tr('battery_opt_request_ignore_btn')),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: openBatteryOptimizationSettings,
                    icon: const Icon(Icons.settings),
                    label: Text(l10n.tr('battery_opt_open_battery_settings_btn')),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: openAppDetailsSettings,
                    icon: const Icon(Icons.info_outline),
                    label: Text(l10n.tr('battery_opt_open_app_settings_btn')),
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.white10),
                  Text(
                    l10n.tr('battery_opt_notes_title'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.tr('battery_opt_notes_body'),
                    style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      l10n.tr('battery_opt_close'),
                      style: const TextStyle(color: Colors.cyanAccent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _stepsForVendor(AppLocalizations l10n, String vendor) {
    vendor = vendor.toLowerCase();

    // Many Tecno/Infinix are Transsion (XOS/HiOS); Oppo/Realme/OnePlus share similar flows.
    if (vendor.contains('samsung')) {
      return l10n.tr('battery_opt_steps_samsung');
    }

    if (vendor.contains('huawei') || vendor.contains('honor')) {
      return l10n.tr('battery_opt_steps_huawei');
    }

    if (vendor.contains('oppo') || vendor.contains('realme') || vendor.contains('oneplus')) {
      return l10n.tr('battery_opt_steps_oppo');
    }

    if (vendor.contains('infinix') ||
        vendor.contains('tecno') ||
        vendor.contains('itel') ||
        vendor.contains('transsion')) {
      return l10n.tr('battery_opt_steps_transsion');
    }

    // Generic fallback
    return l10n.tr('battery_opt_steps_generic');
  }
}

class _StepsBox extends StatelessWidget {
  const _StepsBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Text(
        text.trim(),
        style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
      ),
    );
  }
}
