import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/desktop/desktop_pairing_models.dart';
import '../../core/services/desktop/desktop_pairing_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
import 'web_desktop_session_store.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Breakpoint
// ─────────────────────────────────────────────────────────────────────────────

const double _kDesktopBreakpoint = 768;

bool _isDesktopView(BuildContext context) =>
    MediaQuery.of(context).size.width >= _kDesktopBreakpoint;

// ─────────────────────────────────────────────────────────────────────────────
// WebPairingScreen
// ─────────────────────────────────────────────────────────────────────────────

class WebPairingScreen extends StatefulWidget {
  /// Called when QR pairing OR Google sign-in succeeds on DESKTOP.
  final void Function({
    required String uid,
    required String name,
    required String email,
  })? onPaired;

  /// Called when Google / email sign-in succeeds on MOBILE browser.
  final void Function(User user)? onMobileLogin;

  const WebPairingScreen({
    super.key,
    this.onPaired,
    this.onMobileLogin,
  });

  @override
  State<WebPairingScreen> createState() => _WebPairingScreenState();
}

class _WebPairingScreenState extends State<WebPairingScreen>
    with WidgetsBindingObserver {
  // ── QR session state ──────────────────────────────────────────────────────
  DesktopPairingSession? _session;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  bool _paired = false;

  // ── Google sign-in state ──────────────────────────────────────────────────
  bool _googleLoading = false;
  String? _googleError;

  // ── Email / password state (mobile only) ──────────────────────────────────
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _emailLoading = false;
  String? _emailError;
  bool _obscurePassword = true;
  bool _isSignUp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  // ── QR session ────────────────────────────────────────────────────────────

  Future<void> _boot() async {
    if (!mounted) return;
    _pollTimer?.cancel();

    setState(() {
      _loading = true;
      _error = null;
      _paired = false;
      _session = null;
      _googleError = null;
      _emailError = null;
    });

    try {
      if (Firebase.apps.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        if (Firebase.apps.isEmpty) {
          throw StateError(
            'Firebase is not initialized. Please refresh the page.',
          );
        }
      }

      final session = await DesktopPairingService.instance.createSession();
      if (!mounted) return;

      setState(() {
        _session = session;
        _loading = false;
      });

      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_paired) {
        _pollTimer?.cancel();
        return;
      }

      final current = _session;
      if (current == null) return;

      try {
        final status = await DesktopPairingService.instance.getStatus(
          sessionId: current.sessionId,
          sessionSecret: current.sessionSecret,
        );

        if (!mounted) return;

        if (status.approved ||
            status.status == 'approved' ||
            status.status == 'consumed') {
          _pollTimer?.cancel();
          _paired = true;

          final token = status.firebaseCustomToken.trim();
          if (token.isNotEmpty && Firebase.apps.isNotEmpty) {
            try {
              final auth = FirebaseAuth.instance;
              if (auth.currentUser != null) await auth.signOut();
              await auth.signInWithCustomToken(token);
            } catch (e) {
              debugPrint('Custom token sign-in skipped: $e');
            }
          }

          await WebDesktopSessionStore.save(
            sessionId: current.sessionId,
            sessionSecret: current.sessionSecret,
            pairedUserUid: status.pairedUserUid,
            pairedUserName: status.pairedUserName,
            pairedUserEmail: status.pairedUserEmail,
          );

          if (!mounted) return;
          widget.onPaired?.call(
            uid: status.pairedUserUid,
            name: status.pairedUserName,
            email: status.pairedUserEmail,
          );
          return;
        }

        if (status.status == 'expired' || status.status == 'rejected') {
          _pollTimer?.cancel();
          if (!mounted) return;
          setState(() {
            _error = 'Session expired. Please refresh to scan again.';
          });
        }
      } catch (e) {
        debugPrint('Poll error (will retry): $e');
      }
    });
  }

  // ── Google Sign-In ────────────────────────────────────────────────────────

  Future<void> _signInWithGoogle() async {
    if (_googleLoading) return;
    setState(() {
      _googleLoading = true;
      _googleError = null;
    });

    try {
      final provider = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile');

      final result =
          await FirebaseAuth.instance.signInWithPopup(provider);

      final user = result.user;
      if (user == null) throw Exception('No user returned.');

      if (!mounted) return;

      if (_isDesktopView(context)) {
        // Desktop → save session and call onPaired
        await WebDesktopSessionStore.save(
          sessionId: 'google-direct',
          sessionSecret: 'google-direct',
          pairedUserUid: user.uid,
          pairedUserName: user.displayName ?? '',
          pairedUserEmail: user.email ?? '',
        );
        widget.onPaired?.call(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
        );
      } else {
        // Mobile browser → call onMobileLogin
        widget.onMobileLogin?.call(user);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _googleLoading = false;
        _googleError = _friendlyAuthError(e.code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _googleLoading = false;
        _googleError = e.toString();
      });
    }
  }

  // ── Email / Password ──────────────────────────────────────────────────────

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(
          () => _emailError = 'Please enter your email and password.');
      return;
    }

    setState(() {
      _emailLoading = true;
      _emailError = null;
    });

    try {
      UserCredential cred;

      if (_isSignUp) {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final user = cred.user;
      if (user == null) throw Exception('No user returned.');

      if (!mounted) return;
      widget.onMobileLogin?.call(user);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _emailLoading = false;
        _emailError = _friendlyAuthError(e.code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _emailLoading = false;
        _emailError = e.toString();
      });
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() =>
          _emailError = 'Enter your email first to reset password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Password reset email sent. Check your inbox.'),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _emailError = _friendlyAuthError(e.code));
    }
  }

  String _friendlyAuthError(String code) {
    switch (code) {
      case 'popup-closed-by-user':
        return 'Sign-in cancelled. Please try again.';
      case 'popup-blocked':
        return 'Popup blocked. Allow popups for this site and try again.';
      case 'unauthorized-domain':
        return 'This domain is not authorised. Contact support.';
      case 'operation-not-allowed':
        return 'This sign-in method is not enabled. Contact support.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return 'Something went wrong ($code). Please try again.';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDesktop = _isDesktopView(context);

    return GlassScaffold(
      useBubbles: false,
      body: isDesktop
          ? _buildDesktopLayout(brightness)
          : _buildMobileLayout(brightness),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DESKTOP LAYOUT  (width ≥ 768)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildDesktopLayout(Brightness brightness) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 640;
    final stacked = width < 980;

    if (_loading) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _InfoCard(
              title: 'Preparing desktop session...',
              subtitle:
                  'Please wait while we generate your eSportlyic Web QR login.',
              brightness: brightness,
              child: const Padding(
                padding: EdgeInsets.only(top: 18),
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppTheme.limeAccentDark,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _InfoCard(
              title: 'Could not start desktop pairing',
              subtitle: _error!,
              brightness: brightness,
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: AppTheme.darkText,
                    ),
                    onPressed: () async {
                      _paired = false;
                      await WebDesktopSessionStore.clear();
                      await _boot();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_session == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _InfoCard(
              title: 'No session available',
              subtitle: 'Tap refresh to create a new QR session.',
              brightness: brightness,
              child: Column(
                children: [
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: AppTheme.darkText,
                    ),
                    onPressed: _boot,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useStacked =
              stacked || constraints.maxWidth < 980;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1220),
                child: useStacked
                    ? Column(
                        children: [
                          _DesktopQrPanel(
                            session: _session!,
                            onRefresh: _boot,
                            compact: compact,
                            brightness: brightness,
                            googleLoading: _googleLoading,
                            googleError: _googleError,
                            onGoogleSignIn: _signInWithGoogle,
                          ),
                          const SizedBox(height: 16),
                          _IntroPanel(
                            compact: compact,
                            brightness: brightness,
                          ),
                        ],
                      )
                    : Wrap(
                        spacing: 18,
                        runSpacing: 18,
                        alignment: WrapAlignment.center,
                        crossAxisAlignment:
                            WrapCrossAlignment.start,
                        children: [
                          SizedBox(
                            width: 540,
                            child: _IntroPanel(
                              compact: compact,
                              brightness: brightness,
                            ),
                          ),
                          SizedBox(
                            width: 620,
                            child: _DesktopQrPanel(
                              session: _session!,
                              onRefresh: _boot,
                              compact: compact,
                              brightness: brightness,
                              googleLoading: _googleLoading,
                              googleError: _googleError,
                              onGoogleSignIn: _signInWithGoogle,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE LAYOUT  (width < 768)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildMobileLayout(Brightness brightness) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Brand ──────────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: AppTheme.limeAccent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.limeAccentDark
                                  .withOpacity(0.30),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/icon.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.sports_esports_rounded,
                              color: AppTheme.darkText,
                              size: 38,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'eSportlyic',
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isSignUp
                            ? 'Create your account'
                            : 'Sign in to continue.',
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // ── Google Sign-In ──────────────────────────────────────
                _GoogleButton(
                  loading: _googleLoading,
                  brightness: brightness,
                  onTap: _signInWithGoogle,
                ),

                if (_googleError != null) ...[
                  const SizedBox(height: 10),
                  _ErrorBox(message: _googleError!),
                ],

                // ── Divider ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Divider(
                            color: AppTheme.cardBorder(brightness)),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            color: AppTheme.secondaryText(brightness),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                            color: AppTheme.cardBorder(brightness)),
                      ),
                    ],
                  ),
                ),

                // ── Email field ─────────────────────────────────────────
                Glass(
                  borderRadius: 16,
                  padding: EdgeInsets.zero,
                  fill: AppTheme.searchBackground(brightness),
                  borderColor: AppTheme.searchOutline(brightness),
                  child: TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    style: TextStyle(
                        color: AppTheme.primaryText(brightness)),
                    decoration: InputDecoration(
                      hintText: 'Email',
                      hintStyle: TextStyle(
                          color: AppTheme.secondaryText(brightness)),
                      prefixIcon: Icon(
                        Icons.email_outlined,
                        color: AppTheme.secondaryText(brightness),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Password field ──────────────────────────────────────
                Glass(
                  borderRadius: 16,
                  padding: EdgeInsets.zero,
                  fill: AppTheme.searchBackground(brightness),
                  borderColor: AppTheme.searchOutline(brightness),
                  child: TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    style: TextStyle(
                        color: AppTheme.primaryText(brightness)),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      hintStyle: TextStyle(
                          color: AppTheme.secondaryText(brightness)),
                      prefixIcon: Icon(
                        Icons.lock_outline_rounded,
                        color: AppTheme.secondaryText(brightness),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AppTheme.secondaryText(brightness),
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16),
                    ),
                    onSubmitted: (_) => _submitEmail(),
                  ),
                ),

                // ── Forgot password ─────────────────────────────────────
                if (!_isSignUp)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resetPassword,
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                if (_isSignUp) const SizedBox(height: 12),

                // ── Email error ─────────────────────────────────────────
                if (_emailError != null) ...[
                  const SizedBox(height: 8),
                  _ErrorBox(message: _emailError!),
                ],

                const SizedBox(height: 16),

                // ── Submit button ───────────────────────────────────────
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _emailLoading ? null : _submitEmail,
                  child: _emailLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppTheme.darkText,
                          ),
                        )
                      : Text(
                          _isSignUp ? 'Create account' : 'Sign in',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
                const SizedBox(height: 20),

                // ── Toggle sign in / sign up ────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isSignUp
                          ? 'Already have an account?'
                          : 'No account?',
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _isSignUp = !_isSignUp;
                        _emailError = null;
                        _googleError = null;
                      }),
                      child: Text(
                        _isSignUp ? 'Sign in' : 'Create one',
                        style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final bool loading;
  final Brightness brightness;
  final VoidCallback onTap;

  const _GoogleButton({
    required this.loading,
    required this.brightness,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
          side: BorderSide(
              color: AppTheme.cardBorder(brightness), width: 1.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          foregroundColor: AppTheme.primaryText(brightness),
          backgroundColor: AppTheme.searchBackground(brightness),
        ),
        onPressed: loading ? null : onTap,
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.limeAccentDark,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFF4285F4),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Continue with Google',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Desktop-only widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Brightness brightness;

  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 28,
      padding: const EdgeInsets.all(24),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _IntroPanel extends StatelessWidget {
  final bool compact;
  final Brightness brightness;

  const _IntroPanel({
    required this.compact,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    return Glass(
      borderRadius: 28,
      padding: EdgeInsets.all(compact ? 18 : 24),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _BrandLogo(size: compact ? 54 : 64),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'eSportlyic Web',
                  style:
                      Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppTheme.primaryText(brightness),
                            fontWeight: FontWeight.w900,
                            fontSize: compact ? 28 : 36,
                          ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Use eSportlyic on your computer',
            style:
                Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.primaryText(brightness),
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                      fontSize: compact ? 28 : 54,
                    ),
          ),
          const SizedBox(height: 16),
          Text(
            '1. Open eSportlyic on your phone\n'
            '2. Go to the QR scanner\n'
            '3. Scan this code to link your desktop',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.secondaryText(brightness),
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 18 : 22,
                ),
          ),
          const SizedBox(height: 18),
          Glass(
            borderRadius: 22,
            padding: const EdgeInsets.all(16),
            fill: AppTheme.searchBackground(brightness),
            borderColor: AppTheme.searchOutline(brightness),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: AppTheme.limeAccentDark,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your phone stays the primary device. '
                    'This desktop session is linked securely '
                    'through your mobile app.',
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopQrPanel extends StatelessWidget {
  final DesktopPairingSession session;
  final VoidCallback onRefresh;
  final bool compact;
  final Brightness brightness;
  final bool googleLoading;
  final String? googleError;
  final VoidCallback onGoogleSignIn;

  const _DesktopQrPanel({
    required this.session,
    required this.onRefresh,
    required this.compact,
    required this.brightness,
    required this.googleLoading,
    required this.googleError,
    required this.onGoogleSignIn,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final qrSize = compact ? 220.0 : (width < 1200 ? 260.0 : 300.0);

    return Glass(
      borderRadius: 28,
      padding: EdgeInsets.all(compact ? 18 : 24),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── QR Code ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: session.qrPayload.trim().isEmpty
                ? const SizedBox(
                    width: 260,
                    height: 260,
                    child: Center(
                      child: Text(
                        'QR payload empty',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  )
                : QrImageView(
                    data: session.qrPayload,
                    version: QrVersions.auto,
                    size: qrSize,
                    gapless: true,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
          ),
          const SizedBox(height: 22),

          Text(
            'Scan to link this desktop',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontSize: compact ? 20 : 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Open the eSportlyic mobile app and scan this QR code.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
            ),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh QR'),
          ),

          // ── Divider ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Row(
              children: [
                Expanded(
                    child:
                        Divider(color: AppTheme.cardBorder(brightness))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: AppTheme.secondaryText(brightness),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                    child:
                        Divider(color: AppTheme.cardBorder(brightness))),
              ],
            ),
          ),

          Text(
            'Sign in directly with Google',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          // ── Google button ───────────────────────────────────────────
          _GoogleButton(
            loading: googleLoading,
            brightness: brightness,
            onTap: onGoogleSignIn,
          ),

          if (googleError != null) ...[
            const SizedBox(height: 12),
            _ErrorBox(message: googleError!),
          ],
        ],
      ),
    );
  }
}

class _BrandLogo extends StatelessWidget {
  final double size;
  const _BrandLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppTheme.limeAccent,
        boxShadow: [
          BoxShadow(
            color: AppTheme.limeAccentDark.withOpacity(0.24),
            blurRadius: 22,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.asset(
          'assets/icon.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.sports_esports,
            color: AppTheme.darkText,
            size: 28,
          ),
        ),
      ),
    );
  }
}
