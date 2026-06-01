import 'dart:async';

import '../utils/ua_detector.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../features/call/presentation/call_room_screen.dart';
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
import '../../features/live/presentation/join_match_screen.dart';
import '../../features/live/presentation/live_view_screen.dart';
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
import '../../web_app/presentation/web_desktop_session_store.dart';
import '../../web_app/presentation/web_desktop_shell_screen.dart';
import '../../web_app/presentation/web_pairing_screen.dart';
import '../services/app_admins_service.dart';
import '../services/connectivity_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';

// ---------------------------------------------------------------------------
// Breakpoint
// ---------------------------------------------------------------------------

const double _kWebDesktopBreakpoint = 768;

// ---------------------------------------------------------------------------
// _MobileOnlyScreen
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
                'Download the eSportlyic app to access\n'
                'live matches and voice rooms.',
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
                onPressed: () => GoRouter.of(context).go('/'),
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
// WebJoinScreen
// ---------------------------------------------------------------------------

class WebJoinScreen extends StatefulWidget {
  final String joinCode;
  const WebJoinScreen({super.key, required this.joinCode});

  @override
  State<WebJoinScreen> createState() => _WebJoinScreenState();
}

class _WebJoinScreenState extends State<WebJoinScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _joining = false;
  bool _joined = false;
  String? _error;
  String? _joinedLeagueName;
  String? _joinedLeagueId;
  bool _modeChosen = false;

  String get _code => widget.joinCode.trim().toUpperCase();

  Future<void> _joinAs({required bool asParticipant}) async {
    if (_joining) return;

    final uid =
        (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) {
      setState(() => _error = 'Please sign in and try again.');
      return;
    }

    if (_code.isEmpty) {
      setState(() =>
          _error =
              'No join code found. Please use a valid invite link.');
      return;
    }

    setState(() {
      _joining = true;
      _error = null;
      _modeChosen = true;
    });

    try {
      final query = await _firestore
          .collection('leagues')
          .where('code', isEqualTo: _code)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 20));

      if (query.docs.isEmpty) {
        if (!mounted) return;
        setState(() {
          _joining = false;
          _error =
              "We couldn\u2019t find a league with that code. "
              'Please check the link and try again.';
        });
        return;
      }

      final leagueDoc = query.docs.first;
      final leagueId = leagueDoc.id;
      final data = leagueDoc.data();
      final leagueName =
          (data['name'] as String? ?? 'League').trim();

      final leagueRef =
          _firestore.collection('leagues').doc(leagueId);
      final membershipRef =
          leagueRef.collection('memberships').doc(uid);

      await leagueRef
          .set(
            {
              'memberIds': FieldValue.arrayUnion([uid]),
              'updatedAtMs':
                  DateTime.now().millisecondsSinceEpoch,
            },
            SetOptions(merge: true),
          )
          .timeout(const Duration(seconds: 20));

      if (asParticipant) {
        try {
          final existing = await membershipRef
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 12));

          if (!existing.exists) {
            await membershipRef
                .set(
                  {
                    'id': uid,
                    'leagueId': leagueId,
                    'userId': uid,
                    'teamId': null,
                    'role': 1,
                    'updatedAtMs':
                        DateTime.now().millisecondsSinceEpoch,
                    'version': 1,
                  },
                  SetOptions(merge: true),
                )
                .timeout(const Duration(seconds: 20));
          }
        } catch (membershipError) {
          assert(() {
            debugPrint(
              '[WebJoinScreen] membership write failed '
              '(non-fatal): $membershipError',
            );
            return true;
          }());
        }
      }

      if (!mounted) return;
      setState(() {
        _joining = false;
        _joined = true;
        _joinedLeagueName = leagueName;
        _joinedLeagueId = leagueId;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error =
            'Request timed out. Please check your connection '
            'and try again.';
      });
    } on FirebaseException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'permission-denied'
          ? 'Permission denied. Please make sure you are signed '
            'in and try again.'
          : (e.code == 'unavailable' ||
                  e.code == 'deadline-exceeded')
              ? 'Network error. Please check your connection '
                'and try again.'
              : "We couldn\u2019t complete this action. "
                'Please try again.';
      setState(() {
        _joining = false;
        _error = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: brightness == Brightness.dark
          ? AppTheme.navyBgSoft
          : AppTheme.lightBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: _joined
                ? _buildSuccess(context, brightness, theme)
                : _buildJoin(context, brightness, theme),
          ),
        ),
      ),
    );
  }

  Widget _buildJoin(
    BuildContext context,
    Brightness brightness,
    ThemeData theme,
  ) {
    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(28),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.group_add_rounded,
            color: AppTheme.limeAccentDark,
            size: 52,
          ),
          const SizedBox(height: 16),
          Text(
            'Join League',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You were invited to join a league.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: AppTheme.limeAccentDark.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.limeAccentDark.withOpacity(0.30),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.key_rounded,
                  color: AppTheme.limeAccentDark,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  'Code: $_code',
                  style: TextStyle(
                    color: AppTheme.limeAccentDark,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withOpacity(0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.error.withOpacity(0.30),
                ),
              ),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _joining
                  ? null
                  : () => _joinAs(asParticipant: true),
              icon: _joining
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.darkText,
                      ),
                    )
                  : const Icon(Icons.sports_soccer_rounded),
              label: Text(
                _joining ? 'Joining\u2026' : 'Join as Participant',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8B5CF6),
                side: BorderSide(
                  color: const Color(0xFF8B5CF6).withOpacity(0.40),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: _joining
                  ? null
                  : () => _joinAs(asParticipant: false),
              icon: const Icon(Icons.visibility_rounded),
              label: const Text(
                'Join as Viewer',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                foregroundColor:
                    AppTheme.secondaryText(brightness),
              ),
              onPressed: _joining
                  ? null
                  : () => GoRouter.of(context).go('/leagues'),
              child: const Text(
                'Cancel',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(
    BuildContext context,
    Brightness brightness,
    ThemeData theme,
  ) {
    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(28),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: AppTheme.limeAccentDark,
            size: 64,
          ),
          const SizedBox(height: 20),
          Text(
            'You joined!',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w900,
            ),
          ),
          if (_joinedLeagueName != null) ...[
            const SizedBox(height: 8),
            Text(
              _joinedLeagueName!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppTheme.limeAccentDark,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'You have been added to the league.\n'
            'Open the eSportlyic app to view your leagues,\n'
            'or browse on web below.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.secondaryText(brightness),
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.limeAccent,
                foregroundColor: AppTheme.darkText,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                if (_joinedLeagueId != null) {
                  GoRouter.of(context)
                      .go('/leagues/${_joinedLeagueId!}');
                } else {
                  GoRouter.of(context).go('/leagues');
                }
              },
              icon: const Icon(Icons.sports_esports_rounded),
              label: const Text(
                'View My Leagues',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// WebSessionGateScreen
// ---------------------------------------------------------------------------

class WebSessionGateScreen extends StatefulWidget {
  final String? pendingRoute;
  const WebSessionGateScreen({super.key, this.pendingRoute});

  @override
  State<WebSessionGateScreen> createState() => _WebSessionGateScreenState();
}

class _WebSessionGateScreenState extends State<WebSessionGateScreen>
    with WidgetsBindingObserver {
  bool _checking = true;
  String? _startupError;
  Map<String, String>? _savedSession;
  bool _didNavigatePending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  void _maybeNavigatePending() {
    final pending = (widget.pendingRoute ?? '').trim();
    if (pending.isEmpty) return;
    if (_didNavigatePending) return;
    _didNavigatePending = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        GoRouter.of(context).push(pending);
      } catch (_) {}
    });
  }

  Future<void> _check() async {
    try {
      final saved = await WebDesktopSessionStore.load();
      if (!mounted) return;
      setState(() {
        _savedSession = saved;
        _checking = false;
      });

      // If a session already exists and we have a pending route, go there.
      final uid = (saved?['pairedUserUid'] ?? '').trim();
      if (uid.isNotEmpty) {
        _maybeNavigatePending();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _startupError = e.toString();
        _checking = false;
      });
    }
  }

  void _onPaired({
    required String uid,
    required String name,
    required String email,
  }) {
    if (!mounted) return;

    setState(() {
      _savedSession = {
        'pairedUserUid': uid,
        'pairedUserName': name,
        'pairedUserEmail': email,
        'sessionId': '',
        'sessionSecret': '',
      };
    });

    _maybeNavigatePending();
  }

  void _onMobileLogin(User user) {
    if (!mounted) return;

    // Persist so refresh keeps the user in the shell.
    WebDesktopSessionStore.save(
      sessionId: 'mobile-browser',
      sessionSecret: 'mobile-browser',
      pairedUserUid: user.uid,
      pairedUserName: user.displayName ?? '',
      pairedUserEmail: user.email ?? '',
    );

    setState(() {
      _savedSession = {
        'pairedUserUid': user.uid,
        'pairedUserName': user.displayName ?? '',
        'pairedUserEmail': user.email ?? '',
        'sessionId': 'mobile-browser',
        'sessionSecret': 'mobile-browser',
      };
    });

    _maybeNavigatePending();
  }

  void _onUnlink() {
    WebDesktopSessionStore.clear();
    FirebaseAuth.instance.signOut().catchError((_) {});
    if (!mounted) return;
    setState(() {
      _savedSession = null;
      _checking = false;
      _didNavigatePending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_startupError != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load session:\n$_startupError',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 18),
            ),
          ),
        ),
      );
    }

    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFBEF264)),
        ),
      );
    }

    final session = _savedSession;
    final uid = (session?['pairedUserUid'] ?? '').trim();

    if (uid.isNotEmpty) {
      return WebDesktopShellScreen(
        pairedUserUid: uid,
        pairedUserName: session?['pairedUserName'] ?? '',
        pairedUserEmail: session?['pairedUserEmail'] ?? '',
        onUnlink: _onUnlink,
      );
    }

    // Not logged in (no saved pairing/mobile session):
    // WebPairingScreen decides:
    //  - desktop/chromebook -> QR pairing screen
    //  - mobile browser     -> login/signup screen
    return WebPairingScreen(
      onPaired: _onPaired,
      onMobileLogin: _onMobileLogin,
    );
  }
}

// ---------------------------------------------------------------------------
// AuthRouterRefresh
// ---------------------------------------------------------------------------

enum _ProfileState { unknown, checking, missing, exists }

class AuthRouterRefresh extends ChangeNotifier {
  AuthRouterRefresh() {
    _authSub =
        FirebaseAuth.instance.authStateChanges().listen((user) {
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

    _connSub =
        ConnectivityService.instance.connectionStream.listen((online) {
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
    final providerIds =
        u.providerData.map((p) => p.providerId).toSet();
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
      return e.code == 'unavailable' ||
          e.code == 'deadline-exceeded';
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
        exists ? _ProfileState.exists : _ProfileState.missing,
      );
      return;
    } catch (e) {
      final fallback = (prev == _ProfileState.exists)
          ? _ProfileState.exists
          : _ProfileState.unknown;
      _setProfileState(fallback);

      if (kDebugMode) {
        debugPrint(
          'AuthRouterRefresh: profile check failed uid=$uid → $e',
        );
      }

      if (_isNetworkError(e is Object ? e : Exception('unknown'))) {
        return;
      }
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
// Singleton
// ---------------------------------------------------------------------------

final AuthRouterRefresh authRouterRefresh = AuthRouterRefresh();

// ---------------------------------------------------------------------------
// Admin helpers
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
  initialLocation: kIsWeb ? '/' : '/bootstrap',
  refreshListenable: authRouterRefresh,
  debugLogDiagnostics: kDebugMode,
  redirect: (context, state) {
    AppAdminsService.instance.ensureStarted();

    final loc = state.matchedLocation;
    final uid =
        FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    final inDesktop = loc == '/desktop';
    final inLogin = loc == '/login';
    final inForgot = loc == '/forgot-password';
    final inReset = loc == '/reset-password';
    final inVerifyEmail = loc == '/verify-email';
    final inOnboarding = loc == '/onboarding';
    final inBootstrap = loc == '/bootstrap';
    final inJoin = loc == '/join';

    final inPricingAdmin = loc == '/admin/pricing';
    final inPricingAdmins = loc == '/admin/pricing-admins';
    final inAnalyticsAdmin = loc == '/admin/analytics';
    final inVerificationAdmin =
        loc == '/admin/verification-requests';
    final inMarketplaceAdminUpload =
        loc == '/admin/marketplace-upload';
    final inGlobalChatRequestsAdmin =
        loc == '/admin/global-chat-requests';

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

    if (inJoin && !authRouterRefresh.isSignedIn) {
      final query = state.uri.query;
      final fullPath =
          '/join${query.isNotEmpty ? '?$query' : ''}';
      return '/login?returnTo='
          '${Uri.encodeQueryComponent(fullPath)}';
    }

    if (!authRouterRefresh.isSignedIn) {
      if (inLogin || inForgot || inReset || inVerifyEmail) {
        return null;
      }
      return '/login';
    }

    if (authRouterRefresh.needsEmailVerification) {
      if (inVerifyEmail) return null;
      return '/verify-email';
    }

    if (authRouterRefresh.isCheckingProfile) {
      if (inBootstrap) return null;
      if (inJoin) return null;
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
      if (inLogin ||
          inOnboarding ||
          inBootstrap ||
          inVerifyEmail) {
        return '/';
      }
      return null;
    }

    return null;
  },
  routes: [
    // ── Desktop pairing ────────────────────────────────────────────────
    GoRoute(
      path: '/desktop',
      builder: (context, state) => const WebPairingScreen(),
    ),

    // ── Join deep-link ─────────────────────────────────────────────────
    GoRoute(
      path: '/join',
      builder: (context, state) {
        final code =
            (state.uri.queryParameters['code'] ?? '').trim();
        if (kIsWeb) {
          return WebJoinScreen(joinCode: code);
        }
        return QRScannerScreen(initialJoinCode: code);
      },
    ),

    // ── Auth ───────────────────────────────────────────────────────────
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

    // ── Standalone ─────────────────────────────────────────────────────
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/organizer-feed',
      builder: (context, state) =>
          const FollowedOrganizerFeedScreen(),
    ),
    GoRoute(
      path: '/organizer-discovery',
      builder: (context, state) =>
          const PublicOrganizerDiscoveryScreen(),
    ),

    // ── Call Room ──────────────────────────────────────────────────────
    GoRoute(
      path: '/call',
      builder: (context, state) {
        if (kIsWeb) {
          return const _MobileOnlyScreen(
              featureName: 'Voice Room');
        }
        return const CallRoomScreen();
      },
    ),

    // ── Admin ──────────────────────────────────────────────────────────
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
      builder: (context, state) =>
          const DeveloperAnalyticsDashboardScreen(),
    ),
    GoRoute(
      path: '/admin/verification-requests',
      builder: (context, state) =>
          const OrganizerVerificationRequestsScreen(),
    ),
    GoRoute(
      path: '/admin/marketplace-upload',
      builder: (context, state) =>
          const AdminMarketplaceUploadScreen(),
    ),
    GoRoute(
      path: '/admin/global-chat-requests',
      builder: (context, state) =>
          const GlobalChatAdminRequestsScreen(),
    ),

    // ── Root shell ─────────────────────────────────────────────────────
    GoRoute(
      path: '/',
      builder: (context, state) {
        if (kIsWeb) {
          return const WebSessionGateScreen();
        }
        return const HomeShell();
      },
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
        GoRoute(
          path: 'marketplace',
          builder: (context, state) => const MarketplaceScreen(),
        ),
        GoRoute(
          path: 'global-chat',
          builder: (context, state) => const GlobalChatScreen(),
        ),
        GoRoute(
          path: 'live/join',
          builder: (context, state) {
            if (kIsWeb) {
              return const _MobileOnlyScreen(
                  featureName: 'Live Match');
            }
            return const JoinMatchScreen();
          },
        ),
        GoRoute(
          path: 'live/view/:id',
          builder: (context, state) {
            if (kIsWeb) {
              return const _MobileOnlyScreen(
                  featureName: 'Live Match');
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
              if (map['isHost'] is bool) {
                isHost = map['isHost'] as bool;
              }
              if (map['host'] is String) {
                hostAddress = map['host'] as String;
              }
              if (map['port'] is int) {
                port = map['port'] as int;
              }
              if (map['homeName'] is String) {
                homeName = map['homeName'] as String;
              }
              if (map['awayName'] is String) {
                awayName = map['awayName'] as String;
              }
              if (map['side'] is String) {
                hostSide = map['side'] as String;
              }
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
        GoRoute(
          path: 'master-leagues',
          builder: (context, state) =>
              const MasterLeaguesListScreen(),
          routes: [
            GoRoute(
              path: 'create',
              builder: (context, state) =>
                  const CreateMasterLeagueScreen(),
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  MasterLeagueDetailsScreen(
                masterLeagueId: state.pathParameters['id']!,
              ),
              routes: [
                GoRoute(
                  path: 'chat',
                  builder: (context, state) =>
                      OrganizerChatScreen(
                    masterLeagueId:
                        state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'discipline',
                  builder: (context, state) =>
                      OrganizerDisciplineScreen(
                    masterLeagueId:
                        state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: 'leagues',
          builder: (context, state) =>
              const LeaguesListScreen(),
          routes: [
            GoRoute(
              path: 'create',
              builder: (context, state) =>
                  const LeagueCreationDashboard(),
            ),
            GoRoute(
              path: 'create-wizard',
              builder: (context, state) {
                final extra =
                    state.extra as Map<String, dynamic>? ?? {};
                final masterLeagueId =
                    (extra['masterLeagueId'] as String?)
                            ?.trim() ??
                        '';
                final format = extra['initialFormat']
                    as LeagueFormat?;
                return LeagueCreateWizard(
                  masterLeagueId: masterLeagueId,
                  initialFormat: format,
                );
              },
            ),
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
            GoRoute(
              path: 'join-scanner',
              redirect: (context, state) {
                if (kIsWeb) return '/join';
                return null;
              },
              builder: (context, state) =>
                  const QRScannerScreen(),
            ),
            GoRoute(
              path: 'add-teams',
              builder: (context, state) {
                final extra =
                    state.extra as Map<String, dynamic>? ?? {};
                final leagueId =
                    extra['leagueId'] as String? ?? 'mock-id';
                final format =
                    extra['format'] as LeagueFormat? ??
                        LeagueFormat.classic;
                return AddTeamsScreen(
                    leagueId: leagueId, format: format);
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
                  builder: (context, state) =>
                      LeagueStandingsScreen(
                    id: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'knockout',
                  builder: (context, state) =>
                      KnockoutBracketScreen(
                    leagueId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'knockout-admin',
                  builder: (context, state) => LeagueRoleGuard(
                    leagueId: state.pathParameters['id']!,
                    title: 'Organizer Access Only',
                    message:
                        'Only the organizer or allowed admins '
                        'can manage knockout scores.',
                    child: AdminKnockoutScoreMgmtScreen(
                      leagueId: state.pathParameters['id']!,
                    ),
                  ),
                ),
                GoRoute(
                  path: 'space',
                  builder: (context, state) =>
                      LeagueSpaceRoomScreen(
                    leagueId: state.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'chat',
                  builder: (context, state) =>
                      LeagueChatScreen(
                    leagueId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
            GoRoute(
              path: ':leagueId/fixtures',
              builder: (context, state) => FixturesScreen(
                leagueId:
                    state.pathParameters['leagueId']!,
              ),
            ),
            GoRoute(
              path: ':leagueId/admin-scores',
              builder: (context, state) => LeagueRoleGuard(
                leagueId:
                    state.pathParameters['leagueId']!,
                title: 'Organizer Access Only',
                message:
                    'Only the organizer or allowed admins '
                    'can manage league scores.',
                child: AdminScoreMgmtScreen(
                  leagueId:
                      state.pathParameters['leagueId']!,
                ),
              ),
            ),
            GoRoute(
              path: ':leagueId/admin',
              builder: (context, state) => LeagueRoleGuard(
                leagueId:
                    state.pathParameters['leagueId']!,
                title: 'Organizer Access Only',
                message:
                    'Only the organizer or allowed admins '
                    'can open league settings.',
                child: LeagueAdminScreen(
                  leagueId:
                      state.pathParameters['leagueId']!,
                ),
              ),
            ),
            GoRoute(
              path: ':leagueId/matches/:matchId',
              builder: (context, state) => MatchDetailScreen(
                leagueId:
                    state.pathParameters['leagueId']!,
                matchId: state.pathParameters['matchId']!,
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
