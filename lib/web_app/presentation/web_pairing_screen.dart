import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/desktop/desktop_pairing_models.dart';
import '../../core/services/desktop/desktop_pairing_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/ua_detector.dart';
import '../../core/widgets/glass.dart';
import '../../core/widgets/glass_scaffold.dart';
import 'web_desktop_session_store.dart';

bool _isMobileBrowser(BuildContext context) {
  final width = MediaQuery.of(context).size.width;
  return isRealMobileBrowser(width);
}

class WebPairingScreen extends StatefulWidget {
  /// Desktop pairing success (QR/custom token or Google sign-in on desktop UI).
  final void Function({
    required String uid,
    required String name,
    required String email,
  })? onPaired;

  /// Mobile browser login success (Google or email/password on mobile UI).
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
  DesktopPairingSession? _session;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  bool _paired = false;

  // Google sign-in state
  bool _googleLoading = false;
  String? _googleError;

  // Email/password state (mobile UI)
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
          throw StateError('Firebase is not initialized. Please refresh the page.');
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

          // IMPORTANT FIX:
          // Pairing must result in a valid FirebaseAuth session.
          // If custom-token sign-in fails, do NOT save localStorage session
          // and do NOT proceed to the shell.
          if (token.isEmpty) {
            if (!mounted) return;
            setState(() {
              _paired = false;
              _error = 'Pairing was approved but sign-in token is missing. Please refresh and scan again.';
            });
            return;
          }

          try {
            final auth = FirebaseAuth.instance;
            if (auth.currentUser != null) {
              await auth.signOut();
            }
            final cred = await auth.signInWithCustomToken(token);
            if (cred.user == null) {
              throw StateError('Custom token sign-in returned no user.');
            }
          } catch (e) {
            if (!mounted) return;
            setState(() {
              _paired = false;
              _error = 'Could not sign in to this paired session. Please refresh and scan again.\n\n$e';
            });
            return;
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

      // Works on web. On non-web builds, this screen is typically not used.
      final result = await FirebaseAuth.instance.signInWithPopup(provider);
      final user = result.user;
      if (user == null) throw Exception('No user returned from Google Sign-In');

      if (!mounted) return;

      final mobile = _isMobileBrowser(context);

      if (mobile) {
        widget.onMobileLogin?.call(user);
      } else {
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

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _emailError = 'Please enter your email and password.');
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
      setState(() => _emailError = 'Enter your email first to reset password.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent. Check your inbox.')),
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

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final mobile = _isMobileBrowser(context);

    assert(() {
      debugPrint('[WebPairingScreen] width=${MediaQuery.of(context).size.width} mobile=$mobile kIsWeb=$kIsWeb');
      return true;
    }());

    return GlassScaffold(
      useBubbles: false,
      body: mobile ? _buildMobileLayout(brightness) : _buildDesktopLayout(brightness),
    );
  }

  // ===========================
  // DESKTOP UI (pairing screen)
  // ===========================
  Widget _buildDesktopLayout(Brightness brightness) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final compact = width < 640;
    final stacked = width < 980;

    final session = _session;

    if (_loading) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: _InfoCard(
              title: 'Preparing desktop session...',
              subtitle: 'Please wait while we generate your eSportlyic Web QR login.',
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

    if (session == null) {
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
          final availableWidth = constraints.maxWidth;
          final useStacked = stacked || availableWidth < 980;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1220),
                child: useStacked
                    ? Column(
                        children: [
                          _QrPanel(
                            session: session,
                            onRefresh: _boot,
                            compact: compact,
                            brightness: brightness,
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
                        crossAxisAlignment: WrapCrossAlignment.start,
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
                            child: _QrPanel(
                              session: session,
                              onRefresh: _boot,
                              compact: compact,
                              brightness: brightness,
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

  // ===========================
  // MOBILE UI (login/signup)
  // ===========================
  Widget _buildMobileLayout(Brightness brightness) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                              color: AppTheme.limeAccentDark.withOpacity(0.30),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.sports_esports_rounded,
                          color: AppTheme.darkText,
                          size: 38,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'eSportlyic',
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isSignUp ? 'Create your account' : 'Sign in to continue.',
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Google
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      side: BorderSide(color: AppTheme.cardBorder(brightness), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      foregroundColor: AppTheme.primaryText(brightness),
                      backgroundColor: AppTheme.searchBackground(brightness),
                    ),
                    onPressed: _googleLoading ? null : _signInWithGoogle,
                    child: _googleLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.limeAccentDark,
                            ),
                          )
                        : const Text(
                            'Continue with Google',
                            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                  ),
                ),

                if (_googleError != null) ...[
                  const SizedBox(height: 10),
                  _ErrorBox(message: _googleError!),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Row(
                    children: [
                      Expanded(child: Divider(color: AppTheme.cardBorder(brightness))),
                      const SizedBox(width: 12),
                      Text(
                        'OR',
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Divider(color: AppTheme.cardBorder(brightness))),
                    ],
                  ),
                ),

                Glass(
                  borderRadius: 16,
                  padding: EdgeInsets.zero,
                  fill: AppTheme.searchBackground(brightness),
                  borderColor: AppTheme.searchOutline(brightness),
                  child: TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Email',
                      contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Glass(
                  borderRadius: 16,
                  padding: EdgeInsets.zero,
                  fill: AppTheme.searchBackground(brightness),
                  borderColor: AppTheme.searchOutline(brightness),
                  child: TextField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Password',
                      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    onSubmitted: (_) => _submitEmail(),
                  ),
                ),

                if (!_isSignUp)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resetPassword,
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),

                if (_emailError != null) ...[
                  const SizedBox(height: 10),
                  _ErrorBox(message: _emailError!),
                ],

                const SizedBox(height: 14),

                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _emailLoading ? null : _submitEmail,
                  child: _emailLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.darkText),
                        )
                      : Text(
                          _isSignUp ? 'Create account' : 'Sign in',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                ),

                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isSignUp ? 'Already have an account?' : 'No account?',
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
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800),
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

// ===========================
// Small UI components
// ===========================

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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
        ],
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  final DesktopPairingSession session;
  final VoidCallback onRefresh;
  final bool compact;
  final Brightness brightness;

  const _QrPanel({
    required this.session,
    required this.onRefresh,
    required this.compact,
    required this.brightness,
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
          const SizedBox(height: 10),
          Text(
            'Open the eSportlyic mobile app and scan this QR code.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.limeAccent,
              foregroundColor: AppTheme.darkText,
            ),
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh QR'),
          ),
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
