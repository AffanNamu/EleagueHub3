import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/developer_analytics_dashboard_screen.dart';
import '../../features/admin/organizer_verification_requests_screen.dart';
import '../../features/admin/pricing_admin_screen.dart';
import '../../features/admin/pricing_admins_screen.dart';
import '../../features/auth/data/user_profile_repository.dart';
import '../../features/auth/presentation/bootstrap_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/onboarding_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/chat/presentation/global_chat_admin_requests_screen.dart';
import '../../features/chat/presentation/global_chat_screen.dart';
import '../../features/chat/presentation/league_chat_screen.dart';
import '../../features/chat/presentation/organizer_chat_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/leagues/models/league_format.dart';
import '../../features/leagues/presentation/add_teams_screen.dart';
import '../../features/leagues/presentation/admin_knockout_score_mgmt_screen.dart';
import '../../features/leagues/presentation/admin_score_mgmt_screen.dart';
import '../../features/leagues/presentation/fixtures_screen.dart';
import '../../features/leagues/presentation/knockout_bracket_screen.dart';
import '../../features/leagues/presentation/league_admin_screen.dart';
import '../../features/leagues/presentation/league_create_wizard.dart';
import '../../features/leagues/presentation/league_creation_dashboard.dart';
import '../../features/leagues/presentation/league_creation_payment_screen.dart';
import '../../features/leagues/presentation/league_detail_screen.dart';
import '../../features/leagues/presentation/league_role_guard.dart';
import '../../features/leagues/presentation/league_space_room_screen.dart';
import '../../features/leagues/presentation/league_standings_screen.dart';
import '../../features/leagues/presentation/leagues_list_screen.dart';
import '../../features/leagues/presentation/match_detail_screen.dart';
import '../../features/leagues/presentation/qr_scanner_screen.dart';
import '../../features/marketplace/presentation/admin_marketplace_upload_screen.dart';
import '../../features/marketplace/presentation/marketplace_screen.dart';
import '../../features/master_leagues/presentation/create_master_league_screen.dart';
import '../../features/master_leagues/presentation/followed_organizer_feed_screen.dart';
import '../../features/master_leagues/presentation/master_league_details_screen.dart';
import '../../features/master_leagues/presentation/master_leagues_list_screen.dart';
import '../../features/master_leagues/presentation/organizer_discipline_screen.dart';
import '../../features/master_leagues/presentation/public_organizer_discovery_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/settings_screen.dart';
import '../../web_app/presentation/web_pairing_screen.dart';
import '../services/app_admins_service.dart';
import '../services/connectivity_service.dart';

// ---------------------------------------------------------------------------
// NOTE: CallRoomScreen and LiveViewScreen / JoinMatchScreen are intentionally
// NOT imported on web. Those screens depend on native platform APIs
// (camera, foreground services, WebRTC native stack) that are unavailable
// in a browser context. We guard their routes with kIsWeb checks below.
// ---------------------------------------------------------------------------

// Lazy imports for mobile-only screens so the web compiler tree-shakes them.
// We use a conditional import pattern via factory functions instead of
// top-level imports, because top-level imports are always compiled even
// when guarded by kIsWeb at runtime on the web target.
//
// HOWEVER: since Flutter web compiles everything into one bundle regardless,
// the safest approach for screens that HAVE web-incompatible platform imports
// is to keep them imported but guard the ROUTE BUILDER with kIsWeb.
// The mobile-only screens themselves must internally guard any dart:io usage.
//
// For CallRoomScreen and Live screens we DO guard the route entirely.
import '../../features/call/presentation/call_room_screen.dart';
import '../../features/live/presentation/join_match_screen.dart';
import '../../features/live/presentation/live_view_screen.dart';

// ---------------------------------------------------------------------------
// Web-only error screen shown when a mobile-only route is hit on web
// ---------------------------------------------------------------------------

class _MobileOnlyScreen extends StatelessWidget {
  final String featureName;
  const _MobileOnlyScreen({required this.featureName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.smartphone_rounded,
                color: Color(0xFFBEF264),
                size: 64,
              ),
              const SizedBox(height: 24),
              Text(
                '$featureName is available\non the mobile app only.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Download the eSportlyic app to access\nlive matches and voice rooms.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              TextButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFFBEF264),
                ),
                label: const Text(
                  'Go Back',
                  style: TextStyle(
                    color: Color(0xFFBEF264),
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AuthRouterRefresh — unchanged from original
// ---------------------------------------------------------------------------

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

      if (needsEmailVerification) {
        _setProfileState(_ProfileState.unknown);
        notifyListeners();
        return;
      }

      unawaited(_checkProfileFor(_user!.uid));
    });

    _connSub = ConnectivityService.instance.connectionStream.listen((online) {
      if (!online) {
        _cancelRetry();
        return;
      }

      final uid = _user?.uid;
      if (uid == null) return;
      if (needsEmailVerification) return;

      if (_profileState == _ProfileState.unknown) {
        unawaited(_checkProfileFor(uid));
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

  bool get needsEmailVerification {
    final u = _user;
    if (u == null) return false;
    if (u.isAnonymous) return false;

    final providerIds = u.providerData.map((p) => p.providerId).toSet();
    final isPassword = providerIds.contains('password');
    if (!isPassword) return false;

    return !u.emailVerified;
  }

  bool get isCheckingProfile =>
      isSignedIn &&
      !needsEmailVerification &&
      (_profileState == _ProfileState.unknown ||
          _profileState == _ProfileState.checking);

  bool get needsOnboarding =>
      isSignedIn &&
      !needsEmailVerification &&
      _profileState == _ProfileState.missing;

  bool get hasProfile =>
      isSignedIn &&
      !needsEmailVerification &&
      _profileState == _ProfileState.exists;

  Future<void> refreshAuthUser() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;

    try {
      await u.reload().timeout(const Duration(seconds: 12));
    } catch (_) {}

    _user = FirebaseAuth.instance.currentUser;
    notifyListeners();

    final uid = _user?.uid;
    if (uid == null) return;
    if (needsEmailVerification) return;

    if (_profileState == _ProfileState.unknown) {
      await _checkProfileFor(uid);
    }
  }

  Future<void> refreshProfileStatus() async {
    final uid = _user?.uid;
    if (uid == null) return;
    if (needsEmailVerification) return;
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
    if (e is FirebaseAuthException) {
      return e.code == 'network-request-failed';
    }
    if (e is FirebaseException) {
      return e.code == 'unavailable' || e.code == 'deadline-exceeded';
    }

    final raw = e.toString().toLowerCase();
    if (raw.contains('socketexception')) return true;
    if (raw.contains('network')) return true;
    if (raw.contains('timed out')) return true;
    if (raw.contains('failed host lookup')) return true;

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
          'AuthRouterRefresh: profile check failed for uid=$uid → $e',
        );
      }

      if (_isNetworkError(e is Object ? e : Exception('unknown'))) return;
      if (_retryAttempt >= 5) return;

      final delay = _retryDelayForAttempt(_retryAttempt);
      _retryAttempt++;

      _retryTimer = Timer(delay, () {
        if (_user?.uid != uid) return;
        if (!ConnectivityService.instance.isConnected.value) return;
        if (needsEmailVerification) return;
        unawaited(_checkProfileFor(uid));
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

// ---------------------------------------------------------------------------
// Singleton refresh notifier — unchanged
// ---------------------------------------------------------------------------

final AuthRouterRefresh authRouterRefresh = AuthRouterRefresh();

// ---------------------------------------------------------------------------
// Admin checks — unchanged
// ---------------------------------------------------------------------------

bool _isPricingAdminUidSync(String uid) {
  if (uid.isEmpty) return false;
  return AppAdminsService.instance.isPricingAdminUid(uid);
}

const String _superAdminUid = 'a0JDUelQW3TEyoXTm4ESuGi7ndq1';

bool auth_routerRefreshNeedsOnboardingFix(AuthRouterRefresh r) =>
    r.needsOnboarding;

// ---------------------------------------------------------------------------
// App router
// ---------------------------------------------------------------------------

final appRouter = GoRouter(
  initialLocation: '/bootstrap',
  refreshListenable: authRouterRefresh,
  debugLogDiagnostics: kDebugMode,
  redirect: (context, state) {
    AppAdminsService.instance.ensureStarted();

    final loc = state.matchedLocation;
    final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    final inDesktop = loc == '/desktop';
    final inLogin = loc == '/login';
    final inForgot = loc == '/forgot-password';
    final inReset = loc == '/reset-password';
    final inVerifyEmail = loc == '/verify-email';
    final inOnboarding = loc == '/onboarding';
    final inBootstrap = loc == '/bootstrap';

    final inPricingAdmin = loc == '/admin/pricing';
    final inPricingAdmins = loc == '/admin/pricing-admins';
    final inAnalyticsAdmin = loc == '/admin/analytics';
    final inVerificationAdmin = loc == '/admin/verification-requests';
    final inMarketplaceAdminUpload = loc == '/admin/marketplace-upload';
    final inGlobalChatRequestsAdmin = loc == '/admin/global-chat-requests';

    // ── Web-only: block mobile-only routes at the redirect level ──────────
    // Even if someone manually types /call or /live/* in the browser,
    // redirect them back to home immediately.
    if (kIsWeb) {
      if (loc.startsWith('/live') || loc == '/call') {
        return '/';
      }
    }

    if (kDebugMode) {
      debugPrint(
        '[RouterRedirect] loc=$loc '
        'signedIn=${authRouterRefresh.isSignedIn} '
        'verify=${authRouterRefresh.needsEmailVerification} '
        'checking=${authRouterRefresh.isCheckingProfile} '
        'needsOnboarding=${authRouterRefresh.needsOnboarding} '
        'hasProfile=${authRouterRefresh.hasProfile}',
      );
    }

    if (inDesktop) return null;

    if (!authRouterRefresh.isSignedIn) {
      if (inLogin || inForgot || inReset || inVerifyEmail) return null;
      return '/login';
    }

    if (authRouterRefresh.needsEmailVerification) {
      if (inVerifyEmail) return null;
      return '/verify-email';
    }

    if (authRouterRefresh.isCheckingProfile) {
      if (inBootstrap) return null;
      return '/bootstrap';
    }

    if (auth_routerRefreshNeedsOnboardingFix(authRouterRefresh)) {
      if (inOnboarding) return null;
      return '/onboarding';
    }

    if (inPricingAdmin ||
        inPricingAdmins ||
        inAnalyticsAdmin ||
        inVerificationAdmin) {
      if (!_isPricingAdminUidSync(uid)) return '/';
    }

    if (inMarketplaceAdminUpload) {
      if (uid != _superAdminUid) return '/';
    }

    if (inGlobalChatRequestsAdmin) {
      if (uid != _superAdminUid) return '/';
    }

    if (authRouterRefresh.hasProfile) {
      if (inLogin || inOnboarding || inBootstrap || inVerifyEmail) {
        return '/';
      }
      return null;
    }

    return null;
  },
  routes: [
    // ── Desktop pairing entry point ────────────────────────────────────────
    GoRoute(
      path: '/desktop',
      builder: (context, state) => const WebPairingScreen(),
    ),

    // ── Auth flow ──────────────────────────────────────────────────────────
    GoRoute(
      path: '/bootstrap',
      builder: (context, state) => const BootstrapScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) {
        final qp = state.uri.queryParameters;
        return ResetPasswordScreen(
          emailHint: qp['email'],
          initialCode: qp['oobCode'],
        );
      },
    ),
    GoRoute(
      path: '/verify-email',
      builder: (context, state) {
        final qp = state.uri.queryParameters;
        return VerifyEmailScreen(initialCode: qp['oobCode']);
      },
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),

    // ── Top-level standalone routes ────────────────────────────────────────
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/organizer-feed',
      builder: (context, state) => const FollowedOrganizerFeedScreen(),
    ),
    GoRoute(
      path: '/organizer-discovery',
      builder: (context, state) => const PublicOrganizerDiscoveryScreen(),
    ),

    // ── Call Room — mobile only ────────────────────────────────────────────
    // On web: redirect guard above sends to '/'. This builder is a
    // second safety net in case redirect is somehow bypassed.
    GoRoute(
      path: '/call',
      builder: (context, state) {
        if (kIsWeb) {
          return const _MobileOnlyScreen(featureName: 'Voice Room');
        }
        return const CallRoomScreen();
      },
    ),

    // ── Admin routes ───────────────────────────────────────────────────────
    GoRoute(
      path: '/admin/pricing',
      builder: (context, state) => const PricingAdminScreen(),
    ),
    GoRoute(
      path: '/admin/pricing-admins',
      builder: (context, state) => const PricingAdminsScreen(),
    ),
    GoRoute(
      path: '/admin/analytics',
      builder: (context, state) => const DeveloperAnalyticsDashboardScreen(),
    ),
    GoRoute(
      path: '/admin/verification-requests',
      builder: (context, state) =>
          const OrganizerVerificationRequestsScreen(),
    ),
    GoRoute(
      path: '/admin/marketplace-upload',
      builder: (context, state) => const AdminMarketplaceUploadScreen(),
    ),
    GoRoute(
      path: '/admin/global-chat-requests',
      builder: (context, state) => const GlobalChatAdminRequestsScreen(),
    ),

    // ── Shell + nested routes ──────────────────────────────────────────────
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeShell(),
      routes: [
        // ── Profile ───────────────────────────────────────────────────────
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

        // ── Marketplace ───────────────────────────────────────────────────
        GoRoute(
          path: 'marketplace',
          builder: (context, state) => const MarketplaceScreen(),
        ),

        // ── Global chat ───────────────────────────────────────────────────
        GoRoute(
          path: 'global-chat',
          builder: (context, state) => const GlobalChatScreen(),
        ),

        // ── Live — mobile only ─────────────────────────────────────────────
        // Redirect guard above catches these on web. Builder is a safety net.
        GoRoute(
          path: 'live/join',
          builder: (context, state) {
            if (kIsWeb) {
              return const _MobileOnlyScreen(featureName: 'Live Match');
            }
            return const JoinMatchScreen();
          },
        ),
        GoRoute(
          path: 'live/view/:id',
          builder: (context, state) {
            if (kIsWeb) {
              return const _MobileOnlyScreen(featureName: 'Live Match');
            }

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
              if (map['homeName'] is String) {
                homeName = map['homeName'] as String;
              }
              if (map['awayName'] is String) {
                awayName = map['awayName'] as String;
              }
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

        // ── Master leagues (Organizer Workspaces) ─────────────────────────
        // Both web and mobile now use the SAME real screens.
        // No more kIsWeb branching to deleted web_* versions.
        GoRoute(
          path: 'master-leagues',
          builder: (context, state) => const MasterLeaguesListScreen(),
          routes: [
            GoRoute(
              path: 'create',
              builder: (context, state) => const CreateMasterLeagueScreen(),
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) => MasterLeagueDetailsScreen(
                masterLeagueId: state.pathParameters['id']!,
              ),
              routes: [
                GoRoute(
                  path: 'chat',
                  builder: (context, state) => OrganizerChatScreen(
                    masterLeagueId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'discipline',
                  builder: (context, state) => OrganizerDisciplineScreen(
                    masterLeagueId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),

        // ── Leagues ───────────────────────────────────────────────────────
        // Both web and mobile now use the SAME real screens.
        // No more kIsWeb branching to deleted web_* versions.
        GoRoute(
          path: 'leagues',
          builder: (context, state) => const LeaguesListScreen(),
          routes: [
            // Create entry point — same screen for both platforms
            GoRoute(
              path: 'create',
              builder: (context, state) => const LeagueCreationDashboard(),
            ),

            // Create wizard — same screen for both platforms
            GoRoute(
              path: 'create-wizard',
              builder: (context, state) {
                final extra =
                    state.extra as Map<String, dynamic>? ?? {};
                final masterLeagueId =
                    (extra['masterLeagueId'] as String?)?.trim() ?? '';
                final format =
                    extra['initialFormat'] as LeagueFormat?;
                return LeagueCreateWizard(
                  masterLeagueId: masterLeagueId,
                  initialFormat: format,
                );
              },
            ),

            // Payment screens
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
                return LeagueCreationPaymentScreen(
                    leagueName: leagueName);
              },
            ),

            // QR Scanner — mobile only (camera not available in browser)
            GoRoute(
              path: 'join-scanner',
              builder: (context, state) {
                if (kIsWeb) {
                  return const _MobileOnlyScreen(
                    featureName: 'QR Scanner',
                  );
                }
                return const QRScannerScreen();
              },
            ),

            // Add teams
            GoRoute(
              path: 'add-teams',
              builder: (context, state) {
                final extra =
                    state.extra as Map<String, dynamic>? ?? {};
                final leagueId =
                    extra['leagueId'] as String? ?? 'mock-id';
                final format = extra['format'] as LeagueFormat? ??
                    LeagueFormat.classic;
                return AddTeamsScreen(
                    leagueId: leagueId, format: format);
              },
            ),

            // League detail and its children
            GoRoute(
              path: ':id',
              builder: (context, state) => LeagueDetailScreen(
                leagueId: state.pathParameters['id']!,
              ),
              routes: [
                GoRoute(
                  path: 'standings',
                  builder: (context, state) => LeagueStandingsScreen(
                    id: state.pathParameters['id']!,
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
                  builder: (context, state) => LeagueRoleGuard(
                    leagueId: state.pathParameters['id']!,
                    title: 'Organizer Access Only',
                    message:
                        'Only the organizer or allowed admins can manage knockout scores.',
                    child: AdminKnockoutScoreMgmtScreen(
                      leagueId: state.pathParameters['id']!,
                    ),
                  ),
                ),
                GoRoute(
                  path: 'space',
                  builder: (context, state) => LeagueSpaceRoomScreen(
                    leagueId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'chat',
                  builder: (context, state) => LeagueChatScreen(
                    leagueId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),

            // Fixtures
            GoRoute(
              path: ':leagueId/fixtures',
              builder: (context, state) => FixturesScreen(
                leagueId: state.pathParameters['leagueId']!,
              ),
            ),

            // Admin scores
            GoRoute(
              path: ':leagueId/admin-scores',
              builder: (context, state) => LeagueRoleGuard(
                leagueId: state.pathParameters['leagueId']!,
                title: 'Organizer Access Only',
                message:
                    'Only the organizer or allowed admins can manage league scores.',
                child: AdminScoreMgmtScreen(
                  leagueId: state.pathParameters['leagueId']!,
                ),
              ),
            ),

            // League admin settings
            GoRoute(
              path: ':leagueId/admin',
              builder: (context, state) => LeagueRoleGuard(
                leagueId: state.pathParameters['leagueId']!,
                title: 'Organizer Access Only',
                message:
                    'Only the organizer or allowed admins can open league settings.',
                child: LeagueAdminScreen(
                  leagueId: state.pathParameters['leagueId']!,
                ),
              ),
            ),

            // Match detail
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
