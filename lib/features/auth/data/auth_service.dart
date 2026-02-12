import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
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

  String _friendlyAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'network-request-failed':
        return 'Your network appears to be offline. Please check your connection and try again.';
      case 'invalid-email':
        return 'That email address doesn’t look right. Please check and try again.';
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
      default:
        return "We couldn't sign you in. Please try again.";
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
      final googleUser = await GoogleSignIn().signIn().timeout(const Duration(seconds: 30));
      if (googleUser == null) {
        throw const UserFriendlyException('Sign-in was cancelled.');
      }

      final googleAuth = await googleUser.authentication.timeout(const Duration(seconds: 20));
      final cred = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(cred).timeout(const Duration(seconds: 25));
    } catch (e) {
      _rethrowFriendly(e is Object ? e : Exception('unknown'));
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

  Future<UserCredential> registerWithEmailPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth
          .createUserWithEmailAndPassword(email: email.trim(), password: password)
          .timeout(const Duration(seconds: 25));
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
    // Common providerIds: 'google.com', 'password', 'phone', ...
    final providers = user.providerData.map((p) => p.providerId).where((p) => p.isNotEmpty).toList();
    if (providers.isEmpty) return 'unknown';
    if (providers.contains('google.com')) return 'google.com';
    if (providers.contains('password')) return 'password';
    return providers.first;
  }
}
