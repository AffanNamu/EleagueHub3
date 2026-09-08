// lib/core/sharing/share_service.dart
//
// ShareService — the single entry point for sharing any entity in the
// app. Screens should call `ShareService.instance.share(...)` (usually via
// the [ShareButton] widget) rather than building share URLs or launching
// platform intents themselves.
//
// Requires the following pubspec.yaml dependencies (add if missing):
//   share_plus: ^10.0.0      # native OS share sheet fallback ("More")
//   url_launcher: ^6.2.0     # WhatsApp / Telegram / Facebook / X / SMS
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics/link_analytics_service.dart';
import '../routing/route_resolver.dart';
import 'link_generator.dart';

/// A fully-prepared share payload: the canonical link plus human-readable
/// title/description used to build channel-specific share text.
class SharePayload {
  const SharePayload({
    required this.entity,
    required this.link,
    required this.title,
    this.description = '',
  });

  final ShareableEntity entity;
  final Uri link;
  final String title;
  final String description;

  /// Combined text used for channels that accept a single free-text body
  /// (WhatsApp, Telegram, SMS, system share). Kept short and link-first so
  /// link-unfurling clients still show a clean preview.
  String get shareText {
    final desc = description.trim();
    final head = title.trim().isEmpty ? 'Check this out on eSportlyic' : title.trim();
    if (desc.isEmpty) return '$head\n$link';
    return '$head — $desc\n$link';
  }
}

class ShareService {
  ShareService._internal();
  static final ShareService instance = ShareService._internal();

  SharePayload buildPayload({
    required ShareableEntity entity,
    required String title,
    String description = '',
  }) {
    final link = LinkGenerator.forEntity(entity);
    return SharePayload(
      entity: entity,
      link: link,
      title: title,
      description: description,
    );
  }

  Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> shareToWhatsApp(SharePayload payload) async {
    final encoded = Uri.encodeComponent(payload.shareText);
    final ok = await _launch(Uri.parse('https://wa.me/?text=$encoded'));
    if (ok) {
      LinkAnalyticsService.instance.recordShare(
        entity: payload.entity,
        channel: ShareChannel.whatsapp,
      );
    }
  }

  Future<void> shareToTelegram(SharePayload payload) async {
    final encodedUrl = Uri.encodeComponent(payload.link.toString());
    final encodedText = Uri.encodeComponent(
      payload.title.trim().isEmpty ? 'Check this out on eSportlyic' : payload.title.trim(),
    );
    final ok = await _launch(
      Uri.parse('https://t.me/share/url?url=$encodedUrl&text=$encodedText'),
    );
    if (ok) {
      LinkAnalyticsService.instance.recordShare(
        entity: payload.entity,
        channel: ShareChannel.telegram,
      );
    }
  }

  Future<void> shareToFacebook(SharePayload payload) async {
    final encodedUrl = Uri.encodeComponent(payload.link.toString());
    final ok = await _launch(
      Uri.parse('https://www.facebook.com/sharer/sharer.php?u=$encodedUrl'),
    );
    if (ok) {
      LinkAnalyticsService.instance.recordShare(
        entity: payload.entity,
        channel: ShareChannel.facebook,
      );
    }
  }

  Future<void> shareToX(SharePayload payload) async {
    final encodedUrl = Uri.encodeComponent(payload.link.toString());
    final encodedText = Uri.encodeComponent(
      payload.title.trim().isEmpty ? 'Check this out on eSportlyic' : payload.title.trim(),
    );
    final ok = await _launch(
      Uri.parse('https://twitter.com/intent/tweet?url=$encodedUrl&text=$encodedText'),
    );
    if (ok) {
      LinkAnalyticsService.instance.recordShare(
        entity: payload.entity,
        channel: ShareChannel.x,
      );
    }
  }

  Future<void> shareViaSms(SharePayload payload) async {
    final encoded = Uri.encodeComponent(payload.shareText);
    // `sms:?body=` is the cross-platform-safe form; some Android OEMs
    // require `sms:` with no `?` and a `body=` query — both are covered by
    // letting url_launcher negotiate the platform's canonical SMS URI.
    final ok = await _launch(Uri.parse('sms:?body=$encoded'));
    if (ok) {
      LinkAnalyticsService.instance.recordShare(
        entity: payload.entity,
        channel: ShareChannel.sms,
      );
    }
  }

  Future<void> copyLink(SharePayload payload) async {
    await Clipboard.setData(ClipboardData(text: payload.link.toString()));
    LinkAnalyticsService.instance.recordShare(
      entity: payload.entity,
      channel: ShareChannel.copyLink,
    );
  }

  /// Native OS share sheet — the "More" option, covering every
  /// platform-installed share target not explicitly listed above
  /// (Messenger, Instagram DM, Mail, AirDrop, Nearby Share, etc).
  Future<void> shareViaSystemSheet(SharePayload payload) async {
    await SharePlus.instance.share(
      ShareParams(text: payload.shareText, subject: payload.title),
    );
    LinkAnalyticsService.instance.recordShare(
      entity: payload.entity,
      channel: ShareChannel.systemShare,
    );
  }
}
