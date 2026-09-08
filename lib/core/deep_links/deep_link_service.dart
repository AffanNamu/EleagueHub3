// lib/core/deep_links/deep_link_service.dart
//
// DeepLinkService — resolves an incoming Uri (from app_links, a QR scan,
// or an OS "open with app" intent) for the Universal Sharing entity
// types (user profile, competition, team, post, organizer workspace, and
// any future type registered in RouteResolver) and navigates the app
// directly to the target screen.
//
// This is deliberately separate from web browser routing: when the
// Flutter Web build is loaded directly at e.g. https://esportlyic.com/u/x,
// GoRouter's own route table (see app_router.dart) matches the path and
// renders the right screen with no involvement from this service at all.
// DeepLinkService exists ONLY for links that arrive as an operating-system
// level event on native platforms — i.e. the Android App Links /
// `app_links` package flow already wired up in DeepLinkGate.
//
// DeepLinkGate tries this service AFTER the legacy auth-action-link and
// join-code parsers, and BEFORE giving up silently — see deep_link_gate.dart.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../analytics/link_analytics_service.dart';
import '../routing/route_resolver.dart';

class DeepLinkService {
  DeepLinkService._();

  /// Attempts to handle [uri] as a Universal Sharing entity deep link.
  /// Returns true if the URI matched a known entity pattern (in which
  /// case navigation has been scheduled via [navigate]), false if it did
  /// not match — callers should then try other parsers or ignore the
  /// link silently.
  ///
  /// [navigate] is injected by the caller (typically
  /// `(path) => appRouter.go(path)`) rather than imported directly here,
  /// so this service has no compile-time dependency on the app's router
  /// singleton or its file location.
  static bool tryHandle(Uri uri, {required void Function(String path) navigate}) {
    final entity = RouteResolver.tryParsePublicUri(uri);
    if (entity == null) return false;

    if (!entity.isValid) {
      if (kDebugMode) {
        debugPrint(
          '[DeepLinkService] parsed entity is missing its id/username, '
          'ignoring: $uri',
        );
      }
      return false;
    }

    // Username-addressed entities record their own analytics click once
    // resolution succeeds (see UsernameProfileGateScreen) to avoid
    // double-counting a click that ultimately fails to resolve. Every
    // other (id-addressed) entity type is recorded immediately here,
    // since arriving at the gate screen with a valid id is itself a
    // meaningful "link opened" signal even if the underlying doc has
    // since been deleted (that failure is then a separate, useful signal
    // for a content-health dashboard, not something to hide).
    if (entity.type != ShareableEntityType.userProfile) {
      LinkAnalyticsService.instance.recordClick(
        entity: entity,
        channel: ShareChannel.deepLink,
      );
    }

    final path = RouteResolver.internalPathFor(entity);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        navigate(path);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[DeepLinkService] navigate($path) failed: $e');
        }
      }
    });

    return true;
  }
}
