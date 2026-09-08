// lib/core/routing/route_resolver.dart
//
// ─────────────────────────────────────────────────────────────────────────
// RouteResolver — single source of truth for the Universal Sharing &
// Deep Linking system.
// ─────────────────────────────────────────────────────────────────────────
//
// This file defines:
//   1. ShareableEntityType — every entity type that can be shared/deep
//      linked (user profile, competition, team, post, organizer workspace,
//      plus room for future types like market products, tournaments, etc).
//   2. ShareableEntity — a resolved (type, id/slug) pair.
//   3. RouteResolver — converts between:
//        - Public canonical web URLs   (https://esportlyic.com/u/mohammed)
//        - Internal GoRouter paths     (/profile/AbC123)
//        - ShareableEntity value objects
//
// Adding a NEW shareable entity type (e.g. a future "Tournament" or
// "Market Product") requires touching ONLY this file:
//   1. Add a value to [ShareableEntityType].
//   2. Add its public path segment to [_publicSegmentForType] /
//      [_typeForPublicSegment].
//   3. Add its internal GoRouter path to [internalPathFor].
// No other file needs to change — [DeepLinkService], [LinkGenerator], and
// [ShareService] all delegate to this resolver.
class ShareableEntityType {
  const ShareableEntityType._(this.name);
  final String name;

  static const userProfile = ShareableEntityType._('userProfile');
  static const competition = ShareableEntityType._('competition');
  static const team = ShareableEntityType._('team');
  static const post = ShareableEntityType._('post');
  static const organizerWorkspace =
      ShareableEntityType._('organizerWorkspace');

  /// Reserved for future use — wiring is already in place in
  /// [RouteResolver] so enabling these is a one-line change per type.
  static const marketProduct = ShareableEntityType._('marketProduct');
  static const tournament = ShareableEntityType._('tournament');
  static const news = ShareableEntityType._('news');
  static const achievement = ShareableEntityType._('achievement');

  static const List<ShareableEntityType> values = [
    userProfile,
    competition,
    team,
    post,
    organizerWorkspace,
    marketProduct,
    tournament,
    news,
    achievement,
  ];

  @override
  String toString() => 'ShareableEntityType.$name';

  @override
  bool operator ==(Object other) =>
      other is ShareableEntityType && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// A resolved shareable entity: a type plus its identifying value.
///
/// [id] holds a raw database id (e.g. competition id, team/user id, post
/// id) for entity types that are addressed by id. [username] holds a
/// human-readable slug for entity types addressed by slug (currently only
/// [ShareableEntityType.userProfile] via `/u/{username}`).
///
/// Exactly one of [id] / [username] will be non-empty for a given type —
/// see [RouteResolver.addressingModeFor].
class ShareableEntity {
  const ShareableEntity({
    required this.type,
    this.id = '',
    this.username = '',
  });

  final ShareableEntityType type;
  final String id;
  final String username;

  bool get isValid {
    if (RouteResolver.addressingModeFor(type) == _AddressingMode.slug) {
      return username.trim().isNotEmpty;
    }
    return id.trim().isNotEmpty;
  }

  @override
  String toString() =>
      'ShareableEntity(type: $type, id: "$id", username: "$username")';

  @override
  bool operator ==(Object other) =>
      other is ShareableEntity &&
      other.type == type &&
      other.id == id &&
      other.username == username;

  @override
  int get hashCode => Object.hash(type, id, username);
}

enum _AddressingMode { id, slug }

class RouteResolver {
  RouteResolver._();

  /// The production web host. Every canonical share link is built against
  /// this host regardless of whether the app is currently running on
  /// esportlyic.com, esportlyic.web.app, or a custom Firebase Hosting
  /// preview channel — the canonical link is always the production one so
  /// links shared from any environment resolve correctly for recipients.
  static const String canonicalHost = 'esportlyic.com';

  /// Legacy / alternate web hosts that must still be accepted as INCOMING
  /// deep links (e.g. Firebase Hosting default domains, staging channels)
  /// even though we never GENERATE links using them.
  static const Set<String> acceptedIncomingHosts = <String>{
    'esportlyic.com',
    'www.esportlyic.com',
    'esportlyic.web.app',
    'esportlyic.firebaseapp.com',
  };

  /// Custom URL scheme used for app-to-app / QR-code deep links that don't
  /// go through a web URL at all (kept for backward compatibility with the
  /// legacy join-code flow already shipped in production).
  static const String legacyCustomScheme = 'eleaguehub';

  /// New custom URL scheme reserved for this sharing system's own
  /// non-https deep links (e.g. generated inside native share sheets on
  /// platforms where an https link would otherwise bounce through a
  /// browser first). Mirrors [canonicalHost] in spirit.
  static const String appCustomScheme = 'esportlyic';

  static _AddressingMode addressingModeFor(ShareableEntityType type) {
    if (type == ShareableEntityType.userProfile) return _AddressingMode.slug;
    return _AddressingMode.id;
  }

  // ── Public path segment ↔ entity type ─────────────────────────────────

  static String _publicSegmentForType(ShareableEntityType type) {
    switch (type.name) {
      case 'userProfile':
        return 'u';
      case 'competition':
        // NOTE: the production Next.js web app (esportlyic.com) already
        // serves competition detail pages at `/leagues/{id}` — and its
        // middleware already carves that path out as public (see
        // isPublicLeagueView in web_client's middleware.ts). Rather than
        // asking the web app to add a second, redundant `/competition/`
        // route, this resolver generates/accepts links using the SAME
        // path segment the web app already has live. "Competition" here
        // is purely the public-facing name for what this codebase calls
        // a League internally (see LeagueDetailScreen).
        return 'leagues';
      case 'team':
        return 'team';
      case 'post':
        return 'post';
      case 'organizerWorkspace':
        // Mirrors 'competition' above: the web app already serves
        // organizer workspaces publicly at `/master-leagues/{id}`.
        return 'master-leagues';
      case 'marketProduct':
        return 'market';
      case 'tournament':
        return 'tournament';
      case 'news':
        return 'news';
      case 'achievement':
        return 'achievement';
    }
    throw ArgumentError('Unhandled ShareableEntityType: $type');
  }

  static ShareableEntityType? _typeForPublicSegment(String segment) {
    switch (segment.trim().toLowerCase()) {
      case 'u':
        return ShareableEntityType.userProfile;
      case 'leagues':
      case 'competition': // legacy alias accepted on incoming links only
        return ShareableEntityType.competition;
      case 'team':
        return ShareableEntityType.team;
      case 'post':
        return ShareableEntityType.post;
      case 'master-leagues':
      case 'org': // legacy alias accepted on incoming links only
        return ShareableEntityType.organizerWorkspace;
      case 'market':
        return ShareableEntityType.marketProduct;
      case 'tournament':
        return ShareableEntityType.tournament;
      case 'news':
        return ShareableEntityType.news;
      case 'achievement':
        return ShareableEntityType.achievement;
      default:
        return null;
    }
  }

  // ── Public canonical URL ↔ ShareableEntity ────────────────────────────

  /// Builds the canonical public share URL for [entity], e.g.
  /// `https://esportlyic.com/u/mohammed` or
  /// `https://esportlyic.com/competition/AbC123`.
  static Uri publicUriFor(ShareableEntity entity) {
    final segment = _publicSegmentForType(entity.type);
    final slugOrId = addressingModeFor(entity.type) == _AddressingMode.slug
        ? entity.username.trim()
        : entity.id.trim();
    return Uri.https(canonicalHost, '/$segment/$slugOrId');
  }

  /// Attempts to parse an incoming [Uri] — from a clicked web link, a QR
  /// code, an OS "Open with app" intent, or a pasted link — into a
  /// [ShareableEntity]. Returns null if the URI does not match any known
  /// shareable-entity pattern (callers should fall back to other parsers,
  /// e.g. the legacy join-code / auth-action-link parsers).
  static ShareableEntity? tryParsePublicUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();

    final isAcceptedHttps =
        (scheme == 'https' || scheme == 'http') &&
            acceptedIncomingHosts.contains(host);
    final isAppScheme = scheme == appCustomScheme;

    if (!isAcceptedHttps && !isAppScheme) return null;

    final segments = uri.pathSegments
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    if (segments.isEmpty) return null;

    final type = _typeForPublicSegment(segments.first);
    if (type == null) return null;

    if (segments.length < 2) return null;
    final rawValue = Uri.decodeComponent(segments[1]).trim();
    if (rawValue.isEmpty) return null;

    if (addressingModeFor(type) == _AddressingMode.slug) {
      var username = rawValue;
      if (username.startsWith('@')) username = username.substring(1);
      return ShareableEntity(type: type, username: username.toLowerCase());
    }

    return ShareableEntity(type: type, id: rawValue);
  }

  // ── ShareableEntity ↔ internal GoRouter path ──────────────────────────

  /// Maps a resolved entity to the INTERNAL GoRouter path that actually
  /// renders the screen. For [ShareableEntityType.userProfile] this
  /// requires [resolvedUserId] because the internal profile route is keyed
  /// by Firebase uid, not by username — callers must resolve the username
  /// to a uid first (see UsernameProfileGateScreen / DeepLinkService).
  static String internalPathFor(
    ShareableEntity entity, {
    String? resolvedUserId,
  }) {
    switch (entity.type.name) {
      case 'userProfile':
        final uid = (resolvedUserId ?? '').trim();
        if (uid.isEmpty) {
          // Not yet resolved — route through the gate screen, which
          // resolves the username then redirects. Kept as a valid,
          // navigable path so direct browser refreshes on /u/:username
          // always work even before resolution completes.
          return '/u/${entity.username}';
        }
        return '/profile/$uid';
      case 'competition':
        // Competitions are modeled internally as "leagues" (see
        // LeagueDetailScreen / the existing `/leagues/:id` route used by
        // in-app navigation such as organizer dashboards). The PUBLIC
        // share/deep-link surface uses the clearer "competition" term and
        // its own top-level route (`/competition/:id` ->
        // CompetitionGateScreen, which renders LeagueDetailScreen) so the
        // URL a visitor sees and shares always reads `/competition/{id}`,
        // never the internal `/leagues/{id}` naming.
        return '/competition/${entity.id}';
      case 'team':
        // Teams are modeled as a user's team/squad profile in this app —
        // there is no separate team aggregate root distinct from the
        // owning user's profile (see TeamProfileRepository, which is
        // always keyed by userId). /team/{id} therefore addresses the
        // SAME underlying screen as the public user profile, using the
        // owning user's id as the team id. This indirection is kept as
        // its own case (rather than aliasing directly to 'userProfile')
        // so that a future dedicated Team aggregate can be introduced
        // without any change to callers of RouteResolver.
        //
        // This is intentionally the SAME path GoRouter registers for the
        // public web URL (`/team/:teamId` -> TeamProfileGateScreen) — one
        // route table serves both incoming native deep links (via this
        // resolver) and direct browser navigation, so there is exactly
        // one place that maps an entity to a screen.
        return '/team/${entity.id}';
      case 'post':
        return '/post/${entity.id}';
      case 'organizerWorkspace':
        return '/org/${entity.id}';
      case 'marketProduct':
        return '/marketplace/${entity.id}';
      case 'tournament':
        return '/tournament/${entity.id}';
      case 'news':
        return '/news/${entity.id}';
      case 'achievement':
        return '/achievement/${entity.id}';
    }
    throw ArgumentError('Unhandled ShareableEntityType: ${entity.type}');
  }
}
