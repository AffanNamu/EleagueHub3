import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/pricing_admin_screen.dart';
import '../../features/admin/pricing_admins_screen.dart';
import '../../features/auth/data/user_profile_repository.dart';
import '../../features/auth/presentation/bootstrap_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/call/presentation/call_room_screen.dart';
import '../../features/chat/presentation/global_chat_admin_requests_screen.dart';
import '../../features/chat/presentation/global_chat_screen.dart';
import '../../features/chat/presentation/league_chat_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/leagues/models/league_format.dart';
import '../../features/leagues/presentation/add_teams_screen.dart';
import '../../features/leagues/presentation/admin_knockout_score_mgmt_screen.dart';
import '../../features/leagues/presentation/admin_score_mgmt_screen.dart';
import '../../features/leagues/presentation/coupon_screen.dart';
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
import '../../features/leagues/presentation/premium_access_guard.dart';
import '../../features/leagues/presentation/qr_scanner_screen.dart';
import '../../features/live/presentation/global_live_leagues_screen.dart';
import '../../features/live/presentation/join_match_screen.dart';
import '../../features/live/presentation/live_view_screen.dart';
import '../../features/marketplace/presentation/admin_marketplace_upload_screen.dart';
import '../../features/marketplace/presentation/marketplace_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../services/app_admins_service.dart';
import '../services/connectivity_service.dart';

enum _ProfileState { unknown, checking, missing, exists }

class AuthRouterRefresh extends ChangeNotifier {
  AuthRouterRefresh() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final prevUserId = _user?.uid;
      _user = user;

      AppAdminsService.instance.ensureStarted();

      _cancelRetry();
      _retryAttempt = 0;

      if (_user == null) {
        _setProfileState(_ProfileState.unknown);
        if (prevUserId != null) notifyListeners();
        return;
      }

      _checkProfileFor(_user!.uid);
    });

    _connSub = ConnectivityService.instance.connectionStream.listen((online) {
      if (!online) {
        _cancelRetry();
        return;
      }

      final uid = _user?.uid;
      if (uid == null) return;

      if (_profileState == _ProfileState.unknown) {
        // ignore: discarded_futures
        _checkProfileFor(uid);
      }
    });
  }

  late final StreamSubscription<User?> _authSub;
  late final StreamSubscription<bool> _connSub;

  User? _user;

  final UserProfileRepository _profiles = UserProfileRepository();

  _ProfileState _profileState = _ProfileState.unknown;

  Timer? _retryTimer;
  int _retryAttempt = 0;

  bool get isSignedIn => _user != null;

  bool get isCheckingProfile =>
      isSignedIn &&
      (_profileState == _ProfileState.unknown ||
          _profileState == _ProfileState.checking);

  bool get needsOnboarding =>
      isSignedIn && _profileState == _ProfileState.missing;

  bool get hasProfile =>
      isSignedIn && _profileState == _ProfileState.exists;

  Future<void> refreshProfileStatus() async {
    final uid = _user?.uid;
    if (uid == null) return;
    await _checkProfileFor(uid);
  }

  void _setProfileState(_ProfileState next) {
    if (_profileState == next) return;
    _profileState = next;
    notifyListeners();
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Duration _retryDelayForAttempt(int attempt) {
    final seconds = (1 << attempt).clamp(1, 30);
    return Duration(seconds: seconds);
  }

  bool _isNetworkError(Object e) {
    if (e is TimeoutException) return true;
    if (e is SocketException) return true;
    if (e is FirebaseAuthException) {
      return e.code == 'network-request-failed';
    }
    if (e is FirebaseException) {
      return e.code == 'unavailable' || e.code == 'deadline-exceeded';
    }
    return false;
  }

  Future<void> _checkProfileFor(String uid) async {
    final prev = _profileState;

    _cancelRetry();
    _setProfileState(_ProfileState.checking);

    try {
      final exists = await _profiles
          .profileExists(uid)
          .timeout(const Duration(seconds: 12));
      _retryAttempt = 0;
      _setProfileState(
          exists ? _ProfileState.exists : _ProfileState.missing);
      return;
    } catch (e) {
      final fallback = (prev == _ProfileState.exists)
          ? _ProfileState.exists
          : _ProfileState.unknown;
      _setProfileState(fallback);

      if (kDebugMode) {
        debugPrint(
            'AuthRouterRefresh: profile check failed for uid=$uid → $e');
      }

      if (_isNetworkError(e is Object ? e : Exception('unknown'))) return;

      if (_retryAttempt >= 5) return;

      final delay = _retryDelayForAttempt(_retryAttempt);
      _retryAttempt++;

      _retryTimer = Timer(delay, () {
        if (_user?.uid != uid) return;
        if (!ConnectivityService.instance.isConnected.value) return;
        // ignore: discarded_futures
        _checkProfileFor(uid);
      });
    }
  }

  @override
  void dispose() {
    _cancelRetry();
    _authSub.cancel();
    _connSub.cancel();
    super.dispose();
  }
}

final AuthRouterRefresh authRouterRefresh = AuthRouterRefresh();

bool _isPricingAdminUidSync(String uid) {
  if (uid.isEmpty) return false;
  return AppAdminsService.instance.isPricingAdminUid(uid);
}

const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

final appRouter = GoRouter(
  initialLocation: '/bootstrap',
  refreshListenable: authRouterRefresh,
  redirect: (context, state) {
    AppAdminsService.instance.ensureStarted();

    final loc = state.matchedLocation;

    final inLogin = loc == '/login';
    final inOnboarding = loc == '/onboarding';
    final inBootstrap = loc == '/bootstrap';
    final inPricingAdmin = loc == '/admin/pricing';
    final inPricingAdmins = loc == '/admin/pricing-admins';
    final inMarketplaceAdminUpload = loc == '/admin/marketplace-upload';
    final inGlobalChatRequestsAdmin = loc == '/admin/global-chat-requests';

    if (!authRouterRefresh.isSignedIn) {
      if (inLogin) return null;
      return '/login';
    }

    if (authRouterRefresh.isCheckingProfile) {
      if (inBootstrap) return null;
      return '/bootstrap';
    }

    if (auth_routerRefreshNeedsOnboardingFix(authRouterRefresh)) {
      if (inOnboarding) return null;
      return '/onboarding';
    }

    if (inPricingAdmin || inPricingAdmins) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (!_isPricingAdminUidSync(uid)) {
        return '/';
      }
    }

    if (inMarketplaceAdminUpload) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.trim() != _superAdminUid) {
        return '/';
      }
    }

    if (inGlobalChatRequestsAdmin) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (uid.trim() != _superAdminUid) {
        return '/';
      }
    }

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
      path: '/call',
      builder: (context, state) => const CallRoomScreen(),
    ),

    // ── Pricing Admin (pricing-admin UIDs only) ──────────────────────────
    GoRoute(
      path: '/admin/pricing',
      builder: (context, state) => const PricingAdminScreen(),
    ),
    GoRoute(
      path: '/admin/pricing-admins',
      builder: (context, state) => const PricingAdminsScreen(),
    ),

    // ── Marketplace Admin Upload (super-admin only) ──────────────────────
    GoRoute(
      path: '/admin/marketplace-upload',
      builder: (context, state) => const AdminMarketplaceUploadScreen(),
    ),

    // ── Global Chat Requests Admin (super-admin only) ────────────────────
    GoRoute(
      path: '/admin/global-chat-requests',
      builder: (context, state) => const GlobalChatAdminRequestsScreen(),
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

        // ── Marketplace ──────────────────────────────────────────────────
        GoRoute(
          path: 'marketplace',
          builder: (context, state) => const MarketplaceScreen(),
        ),

        // ── Global Live ──────────────────────────────────────────────────
        GoRoute(
          path: 'global-live',
          builder: (context, state) => const GlobalLiveLeaguesScreen(),
        ),

        // ── Global Chat ──────────────────────────────────────────────────
        GoRoute(
          path: 'global-chat',
          builder: (context, state) => const GlobalChatScreen(),
        ),

        // ── Live ─────────────────────────────────────────────────────────
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

        // ── Leagues ──────────────────────────────────────────────────────
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
                      if (map['leagueName'] is String) {
                        leagueName = map['leagueName'] as String;
                      }
                    }
                    return LeagueCreationPaymentScreen(
                        leagueName: leagueName);
                  },
                ),
              ],
            ),
            GoRoute(
              path: ':leagueId/upgrade/payment',
              builder: (context, state) {
                final extra = state.extra;
                String leagueName = 'League';
                if (extra is Map) {
                  final map = extra.cast<dynamic, dynamic>();
                  if (map['leagueName'] is String) {
                    leagueName = map['leagueName'] as String;
                  }
                }
                return LeagueCreationPaymentScreen(leagueName: leagueName);
              },
            ),
            GoRoute(
              path: 'join-scanner',
              builder: (context, state) => const QRScannerScreen(),
            ),
            GoRoute(
              path: 'add-teams',
              builder: (context, state) {
                final extra =
                    state.extra as Map<String, dynamic>? ?? {};
                final leagueId =
                    extra['leagueId'] as String? ?? 'mock-id';
                final format =
                    extra['format'] as LeagueFormat? ?? LeagueFormat.classic;
                return AddTeamsScreen(leagueId: leagueId, format: format);
              },
            ),

            // ── League Detail (HARD PROTECTED) ────────────────────────────
            GoRoute(
              path: ':id',
              builder: (context, state) {
                final leagueId = state.pathParameters['id']!;
                return LeagueAccessGuard(
                  leagueId: leagueId,
                  child: LeagueDetailScreen(leagueId: leagueId),
                );
              },
              routes: [
                GoRoute(
                  path: 'coupon',
                  builder: (context, state) {
                    final leagueId = state.pathParameters['id']!;
                    return CouponScreen(leagueId: leagueId);
                  },
                ),
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
                  builder: (context, state) => LeagueAccessGuard(
                    leagueId: state.pathParameters['id']!,
                    child: KnockoutBracketScreen(
                      leagueId: state.pathParameters['id']!,
                    ),
                  ),
                ),
                GoRoute(
                  path: 'knockout-admin',
                  builder: (context, state) => LeagueAccessGuard(
                    leagueId: state.pathParameters['id']!,
                    child: AdminKnockoutScoreMgmtScreen(
                      leagueId: state.pathParameters['id']!,
                    ),
                  ),
                ),
                GoRoute(
                  path: 'space',
                  builder: (context, state) => LeagueAccessGuard(
                    leagueId: state.pathParameters['id']!,
                    child: LeagueSpaceRoomScreen(
                      leagueId: state.pathParameters['id']!,
                    ),
                  ),
                ),
                GoRoute(
                  path: 'chat',
                  builder: (context, state) => LeagueAccessGuard(
                    leagueId: state.pathParameters['id']!,
                    child: LeagueChatScreen(
                      leagueId: state.pathParameters['id']!,
                    ),
                  ),
                ),
              ],
            ),

            // ── Additional League Routes (protected) ──────────────────────
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
              builder: (context, state) => LeagueAccessGuard(
                leagueId: state.pathParameters['leagueId']!,
                child: AdminScoreMgmtScreen(
                  leagueId: state.pathParameters['leagueId']!,
                ),
              ),
            ),
            GoRoute(
              path: ':leagueId/admin',
              builder: (context, state) => LeagueAccessGuard(
                leagueId: state.pathParameters['leagueId']!,
                child: LeagueAdminScreen(
                  leagueId: state.pathParameters['leagueId']!,
                ),
              ),
            ),
            GoRoute(
              path: ':leagueId/matches/:matchId',
              builder: (context, state) => LeagueAccessGuard(
                leagueId: state.pathParameters['leagueId']!,
                child: MatchDetailScreen(
                  leagueId: state.pathParameters['leagueId']!,
                  matchId: state.pathParameters['matchId']!,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Fix: avoid typo-driven analyzer breaks if you later refactor these booleans.
bool auth_routerRefreshNeedsOnboardingFix(AuthRouterRefresh r) =>
    r.needsOnboarding;
