//lib/features/auth/data/auth_service.dart
import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// User-safe exception: if UI shows `$e`, it will still be a friendly message.
class UserFriendlyException implements Exception {
  final String message;
  const UserFriendlyException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  AuthService();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // debugPrint is NOT stripped from release builds (it only throttles
  // output) -- these calls log emails, token-presence flags, uids, and
  // raw provider error text, all readable off a shipped device's system
  // log (e.g. via ADB) by anything with log-reading access. Gated behind
  // kDebugMode so none of it reaches a production build.
  void _authDebugLog(String message) {
    if (kDebugMode) debugPrint(message);
  }

  /// Action links (verification + password reset) will redirect to:
  /// https://<projectId>.web.app/auth?mode=...&oobCode=...
  ///
  /// That page (Firebase Hosting) immediately redirects to:
  /// eleaguehub://auth?mode=...&oobCode=...
  ///
  /// This stays on Firebase free tier and requires no paid email provider.
  ActionCodeSettings _actionCodeSettings() {
    final projectId = _auth.app.options.projectId;
    final continueUrl = Uri.https('$projectId.web.app', '/auth').toString();

    return ActionCodeSettings(
      url: continueUrl,

      // Key detail:
      // This encourages Firebase to pass the action code to our continue URL so the app can handle it.
      // (instead of always showing the web UI).
      handleCodeInApp: true,
    );
  }

  String _friendlyAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'Your network appears to be offline. Please check your connection and try again.';
      case 'invalid-email':
        return 'That email address doesn\'t look right. Please check and try again.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists for that email. Please sign in instead.';
      case 'weak-password':
        return 'Your password is too weak. Please choose a stronger password.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'operation-not-allowed':
        return 'This sign-in method is not available right now.';

      // Action code flows (verification / reset password)
      case 'expired-action-code':
        return 'That code has expired. Please request a new email and try again.';
      case 'invalid-action-code':
        return 'That code is invalid. Please double-check and try again.';
      case 'user-token-expired':
        return 'Your session has expired. Please sign in again.';
      case 'requires-recent-login':
        return 'For security, please sign in again and retry.';
      default:
        return "We couldn't complete that request. Please try again.";
    }
  }

  Never _rethrowFriendly(Object error) {
    if (error is UserFriendlyException) throw error;

    if (error is SocketException) {
      throw const UserFriendlyException(
        'Your network appears to be offline. Please check your connection and try again.',
      );
    }

    if (error is TimeoutException) {
      throw const UserFriendlyException(
        'Your internet connection seems unstable. Please try again.',
      );
    }

    if (error is FirebaseAuthException) {
      throw UserFriendlyException(_friendlyAuthMessage(error));
    }

    throw const UserFriendlyException('Something went wrong. Please try again.');
  }

  User? get currentUser => _auth.currentUser;

  Future<void> reloadCurrentUser() async {
    try {
      final u = _auth.currentUser;
      if (u == null) return;
      await u.reload().timeout(const Duration(seconds: 15));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Used when the app supports "no explicit login" flows.
  /// NOTE: Must enable Anonymous auth in Firebase Console.
  Future<UserCredential> signInAnonymously() async {
    try {
      return await _auth.signInAnonymously().timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      _authDebugLog('GOOGLE_AUTH: Starting Google Sign-In...');

      final googleSignIn = GoogleSignIn(scopes: ['email']);

      // Ensure any previous session is cleared
      await googleSignIn.signOut().catchError((_) => null);

      _authDebugLog('GOOGLE_AUTH: Calling signIn()...');
      final googleUser = await googleSignIn.signIn().timeout(const Duration(seconds: 30));

      if (googleUser == null) {
        _authDebugLog('GOOGLE_AUTH: User cancelled sign-in');
        throw const UserFriendlyException('Sign-in was cancelled.');
      }

      _authDebugLog('GOOGLE_AUTH: Got user: ${googleUser.email}');
      _authDebugLog('GOOGLE_AUTH: Getting authentication tokens...');

      final googleAuth = await googleUser.authentication.timeout(const Duration(seconds: 20));

      _authDebugLog('GOOGLE_AUTH: accessToken present: ${googleAuth.accessToken != null}');
      _authDebugLog('GOOGLE_AUTH: idToken present: ${googleAuth.idToken != null}');

      if (googleAuth.idToken == null) {
        _authDebugLog('GOOGLE_AUTH: CRITICAL — idToken is null!');
        _authDebugLog('GOOGLE_AUTH: This means default_web_client_id is wrong or missing');
        throw const UserFriendlyException(
          'Google Sign-In configuration error. Please contact support.',
        );
      }

      final cred = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      _authDebugLog('GOOGLE_AUTH: Signing into Firebase...');
      final result = await _auth.signInWithCredential(cred).timeout(const Duration(seconds: 25));
      _authDebugLog('GOOGLE_AUTH: SUCCESS — uid: ${result.user?.uid}');

      return result;
    } catch (e, stackTrace) {
      _authDebugLog('GOOGLE_AUTH: ERROR — ${e.runtimeType}:$e');
      _authDebugLog('GOOGLE_AUTH: STACK — $stackTrace');

      // Re-throw UserFriendlyException as-is
      if (e is UserFriendlyException) rethrow;

      // Show the REAL error for debugging (temporary — remove after fixing)
      if (e is FirebaseAuthException) {
        _authDebugLog('GOOGLE_AUTH: FirebaseAuth code: ${e.code}, message:${e.message}');
        throw UserFriendlyException('Google sign-in failed: ${e.code} —${e.message}');
      }

      // Show platform exceptions (this is where error code 10 appears)
      _authDebugLog('GOOGLE_AUTH: Raw error for debugging: $e');
      throw UserFriendlyException('Google sign-in failed: $e');
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Sign in with Apple (iOS only for now — Android has no native Apple SDK
  // and needs a Service ID + redirect URI registered in the Apple Developer
  // account before its web-redirect flow can work; see login_screen.dart's
  // platform gate on this button).
  // ────────────────────────────────────────────────────────────────────────────

  Future<UserCredential> signInWithApple() async {
    try {
      _authDebugLog('APPLE_AUTH: Starting Apple Sign-In...');

      final provider = AppleAuthProvider();
      provider.addScope('email');
      provider.addScope('name'); // Firebase automatically handles mapping this to user.displayName

      _authDebugLog('APPLE_AUTH: Signing into Firebase...');
      // signInWithProvider natively manages the iOS bottom sheet, nonces, and the secure token exchange.
      // This bypasses the OAuthProvider iOS bridge bug entirely.
      final result = await _auth.signInWithProvider(provider).timeout(const Duration(seconds: 60));
      _authDebugLog('APPLE_AUTH: SUCCESS — uid: ${result.user?.uid}');

      return result;
    } catch (e, stackTrace) {
      _authDebugLog('APPLE_AUTH: ERROR — ${e.runtimeType}:$e');
      _authDebugLog('APPLE_AUTH: STACK — $stackTrace');

      if (e is UserFriendlyException) rethrow;

      if (e is FirebaseAuthException) {
        if (e.code == 'canceled' || e.code == 'web-context-cancelled') {
          throw const UserFriendlyException('Sign-in was cancelled.');
        }
        _authDebugLog('APPLE_AUTH: FirebaseAuth code: ${e.code}, message:${e.message}');
        throw UserFriendlyException('Apple sign-in failed: ${e.code} —${e.message}');
      }

      _authDebugLog('APPLE_AUTH: Raw error for debugging: $e');
      throw UserFriendlyException('Apple sign-in failed: $e');
    }
  }

  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth
          .signInWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Registers a password-based account and triggers Firebase's built-in
  /// email verification flow (free tier / no custom SMTP needed).
  Future<UserCredential> registerWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth
          .createUserWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 25));

      try {
        final user = cred.user;
        if (user != null) {
          await user.sendEmailVerification(_actionCodeSettings()).timeout(const Duration(seconds: 20));
        }
      } on FirebaseAuthException catch (e) {
        throw UserFriendlyException(_friendlyAuthMessage(e));
      }

      return cred;
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Forgot password (Firebase built-in email) + in-app code/link entry
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _auth
          .sendPasswordResetEmail(
            email: email.trim(),
            actionCodeSettings: _actionCodeSettings(),
          )
          .timeout(const Duration(seconds: 25));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Validates a password reset action code and returns the email address.
  Future<String> verifyPasswordResetCode({required String code}) async {
    try {
      return await _auth.verifyPasswordResetCode(code).timeout(const Duration(seconds: 25));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Confirms the reset using the Firebase-issued action code (oobCode) and the new password.
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    try {
      await _auth.confirmPasswordReset(code: code, newPassword: newPassword).timeout(
            const Duration(seconds: 25),
          );
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Email verification (Firebase built-in email) + in-app code/link entry
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> sendEmailVerification() async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw const UserFriendlyException('You are signed out. Please sign in again.');
      await user.sendEmailVerification(_actionCodeSettings()).timeout(const Duration(seconds: 20));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  /// Applies the verification action code from Firebase's verification email.
  Future<void> applyEmailVerificationCode({required String code}) async {
    try {
      await _auth.applyActionCode(code).timeout(const Duration(seconds: 25));
      await reloadCurrentUser();
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut().timeout(const Duration(seconds: 15));
      try {
        await GoogleSignIn().signOut().timeout(const Duration(seconds: 10));
      } catch (_) {
        // no-op
      }
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
    }
  }

  static String detectAuthProvider(User user) {
    // Common providerIds: 'google.com', 'apple.com', 'password', 'phone', ...
    final providers = user.providerData.map((p) => p.providerId).where((p) => p.isNotEmpty).toList();
    if (providers.isEmpty) return 'unknown';
    if (providers.contains('google.com')) return 'google.com';
    if (providers.contains('apple.com')) return 'apple.com';
    if (providers.contains('password')) return 'password';
    return providers.first;
  }
}
