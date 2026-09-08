// lib/core/sharing/link_generator.dart
//
// LinkGenerator — builds the canonical public https://esportlyic.com/...
// share URL for any shareable entity. This is the ONLY place that should
// construct a public share link; every screen's share button goes through
// here (directly or via ShareService) so link format changes never need
// to be hunted down across the UI layer.
import '../routing/route_resolver.dart';

class LinkGenerator {
  LinkGenerator._();

  /// `https://esportlyic.com/u/{username}` — no leading '@'.
  static Uri userProfile(String username) {
    var clean = username.trim().toLowerCase();
    if (clean.startsWith('@')) clean = clean.substring(1);
    return RouteResolver.publicUriFor(
      ShareableEntity(type: ShareableEntityType.userProfile, username: clean),
    );
  }

  /// `https://esportlyic.com/competition/{competitionId}`
  static Uri competition(String competitionId) {
    return RouteResolver.publicUriFor(
      ShareableEntity(
        type: ShareableEntityType.competition,
        id: competitionId.trim(),
      ),
    );
  }

  /// `https://esportlyic.com/team/{teamId}` — teamId is the owning user's
  /// id (see RouteResolver.internalPathFor for why).
  static Uri team(String teamId) {
    return RouteResolver.publicUriFor(
      ShareableEntity(type: ShareableEntityType.team, id: teamId.trim()),
    );
  }

  /// `https://esportlyic.com/post/{postId}`
  static Uri post(String postId) {
    return RouteResolver.publicUriFor(
      ShareableEntity(type: ShareableEntityType.post, id: postId.trim()),
    );
  }

  /// `https://esportlyic.com/org/{workspaceId}`
  static Uri organizerWorkspace(String workspaceId) {
    return RouteResolver.publicUriFor(
      ShareableEntity(
        type: ShareableEntityType.organizerWorkspace,
        id: workspaceId.trim(),
      ),
    );
  }

  /// Generic entry point — prefer the typed helpers above at call sites;
  /// this exists for generic UI code (e.g. a single ShareButton widget)
  /// that receives a [ShareableEntity] value rather than a raw id.
  static Uri forEntity(ShareableEntity entity) =>
      RouteResolver.publicUriFor(entity);

  static String displayString(Uri uri) => uri.toString();
}
