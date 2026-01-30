import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/bootstrap_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/leagues/models/league_format.dart';
import '../../features/leagues/presentation/add_teams_screen.dart';
import '../../features/leagues/presentation/admin_knockout_score_mgmt_screen.dart';
import '../../features/leagues/presentation/admin_score_mgmt_screen.dart';
import '../../features/leagues/presentation/fixtures_screen.dart';
import '../../features/leagues/presentation/knockout_bracket_screen.dart';
import '../../features/leagues/presentation/league_access_guard.dart';
import '../../features/leagues/presentation/league_admin_screen.dart';
import '../../features/leagues/presentation/league_creation_dashboard.dart';
import '../../features/leagues/presentation/league_creation_payment_screen.dart';
import '../../features/leagues/presentation/league_detail_screen.dart';
import '../../features/leagues/presentation/league_space_room_screen.dart';
import '../../features/leagues/presentation/league_standings_screen.dart';
import '../../features/leagues/presentation/leagues_list_screen.dart';
import '../../features/leagues/presentation/match_detail_screen.dart';
import '../../features/leagues/presentation/qr_scanner_screen.dart';
import '../../features/live/presentation/join_match_screen.dart';
import '../../features/live/presentation/live_view_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../../features/auth/data/user_profile_repository.dart';

enum _ProfileState { unknown, checking, missing, exists }

class AuthRouterRefresh extends ChangeNotifier {
  AuthRouterRefresh() {
    _sub = FirebaseAuth.instance.authStateChanges().listen((user) {
      _user = user;
      if (_user == null) {
        _profileState = _ProfileState.unknown;
        notifyListeners();
        return;
      }
      _checkProfileFor(_user!.uid);
    });
  }

  late final StreamSubscription<User?> _sub;
  User? _user;

  final UserProfileRepository _profiles = UserProfileRepository();

  _ProfileState _profileState = _ProfileState.unknown;

  bool get isSignedIn => _user != null;

  bool get isCheckingProfile =>
      isSignedIn && (_profileState == _ProfileState.unknown || _profileState == _ProfileState.checking);

  bool get needsOnboarding => isSignedIn && _profileState == _ProfileState.missing;

  bool get hasProfile => isSignedIn && _profileState == _ProfileState.exists;

  Future<void> refreshProfileStatus() async {
    final uid = _user?.uid;
    if (uid == null) return;
    await _checkProfileFor(uid);
  }

  Future<void> _checkProfileFor(String uid) async {
    _profileState = _ProfileState.checking;
    notifyListeners();

    try {
      final exists = await _profiles.profileExists(uid);
      _profileState = exists ? _ProfileState.exists : _ProfileState.missing;
    } catch (_) {
      // Fail "safe" to onboarding if we can't confirm existence.
      _profileState = _ProfileState.missing;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final AuthRouterRefresh authRouterRefresh = AuthRouterRefresh();

final appRouter = GoRouter(
  initialLocation: '/bootstrap',
  refreshListenable: authRouterRefresh,
  redirect: (context, state) {
    final loc = state.matchedLocation;

    final inLogin = loc == '/login';
    final inOnboarding = loc == '/onboarding';
    final inBootstrap = loc == '/bootstrap';

    // Not signed in -> force login.
    if (!authRouterRefresh.isSignedIn) {
      if (inLogin) return null;
      return '/login';
    }

    // Signed in, but still checking profile -> show bootstrap loader.
    if (authRouterRefresh.isCheckingProfile) {
      if (inBootstrap) return null;
      return '/bootstrap';
    }

    // Signed in, profile missing -> force one-time onboarding.
    if (authRouterRefresh.needsOnboarding) {
      if (inOnboarding) return null;
      return '/onboarding';
    }

    // Signed in + profile exists -> keep them out of auth screens.
    if (authRouterRefresh.hasProfile) {
      if (inLogin || inOnboarding || inBootstrap) return '/';
      return null;
    }

    return null;
  },
  routes: [
    GoRoute(
      path: '/bootstrap',
      builder: (context, state) => const BootstrapScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeShell(),
      routes: [
        GoRoute(
          path: 'profile',
          builder: (context, state) => const ProfileScreen(),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),

        // LIVE
        GoRoute(
          path: 'live/join',
          builder: (context, state) => const JoinMatchScreen(),
        ),
        GoRoute(
          path: 'live/view/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;

            bool isHost = false;
            String? hostAddress;
            int? port;
            String? homeName;
            String? awayName;
            String? hostSide;

            final extra = state.extra;
            if (extra is bool) {
              isHost = extra;
            } else if (extra is Map) {
              final map = extra.cast<dynamic, dynamic>();
              if (map['isHost'] is bool) isHost = map['isHost'] as bool;
              if (map['host'] is String) hostAddress = map['host'] as String;
              if (map['port'] is int) port = map['port'] as int;
              if (map['homeName'] is String) homeName = map['homeName'] as String;
              if (map['awayName'] is String) awayName = map['awayName'] as String;
              if (map['side'] is String) hostSide = map['side'] as String;
            }

            return LiveViewScreen(
              matchId: id,
              isHost: isHost,
              hostAddress: hostAddress,
              port: port,
              homeName: homeName,
              awayName: awayName,
              hostSide: hostSide,
            );
          },
        ),

        // LEAGUES
        GoRoute(
          path: 'leagues',
          builder: (context, state) => const LeaguesListScreen(),
          routes: [
            GoRoute(
              path: 'create',
              builder: (context, state) => const LeagueCreationDashboard(),
              routes: [
                GoRoute(
                  path: 'payment',
                  builder: (context, state) {
                    final extra = state.extra;
                    String leagueName = 'League';
                    if (extra is Map) {
                      final map = extra.cast<dynamic, dynamic>();
                      if (map['leagueName'] is String) leagueName = map['leagueName'] as String;
                    }
                    return LeagueCreationPaymentScreen(leagueName: leagueName);
                  },
                ),
              ],
            ),
            GoRoute(
              path: 'join-scanner',
              builder: (context, state) => const QRScannerScreen(),
            ),
            GoRoute(
              path: 'add-teams',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                final leagueId = extra['leagueId'] as String? ?? 'mock-id';
                final format = extra['format'] as LeagueFormat? ?? LeagueFormat.classic;
                return AddTeamsScreen(leagueId: leagueId, format: format);
              },
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) => LeagueDetailScreen(
                leagueId: state.pathParameters['id']!,
              ),
              routes: [
                GoRoute(
                  path: 'standings',
                  builder: (context, state) => LeagueAccessGuard(
                    leagueId: state.pathParameters['id']!,
                    child: LeagueStandingsScreen(
                      id: state.pathParameters['id']!,
                    ),
                  ),
                ),
                GoRoute(
                  path: 'knockout',
                  builder: (context, state) => KnockoutBracketScreen(
                    leagueId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'knockout-admin',
                  builder: (context, state) => AdminKnockoutScoreMgmtScreen(
                    leagueId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'space',
                  builder: (context, state) => LeagueSpaceRoomScreen(
                    leagueId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
            GoRoute(
              path: ':leagueId/fixtures',
              builder: (context, state) => LeagueAccessGuard(
                leagueId: state.pathParameters['leagueId']!,
                child: FixturesScreen(
                  leagueId: state.pathParameters['leagueId']!,
                ),
              ),
            ),
            GoRoute(
              path: ':leagueId/admin-scores',
              builder: (context, state) => AdminScoreMgmtScreen(
                leagueId: state.pathParameters['leagueId']!,
              ),
            ),
            GoRoute(
              path: ':leagueId/admin',
              builder: (context, state) => LeagueAdminScreen(
                leagueId: state.pathParameters['leagueId']!,
              ),
            ),
            GoRoute(
              path: ':leagueId/matches/:matchId',
              builder: (context, state) => MatchDetailScreen(
                leagueId: state.pathParameters['leagueId']!,
                matchId: state.pathParameters['matchId']!,
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
