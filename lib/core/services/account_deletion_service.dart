import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ---------------------------------------------------------------------------
// AccountDeletionReauth
//
// Outcome of re-verifying the user's identity BEFORE anything is deleted.
// Firebase rejects user.delete() with requires-recent-login once a session
// is more than a few minutes old; previously that surfaced only after the
// server cleanup, Storage deletion and local reset had already run, leaving
// a half-deleted account and a "sign in again" message with no way to do
// so. Re-authenticating first means a failure or cancellation here leaves
// every piece of the account untouched.
// ---------------------------------------------------------------------------

class AccountDeletionReauth {
  const AccountDeletionReauth._({
    required this.ok,
    this.cancelled = false,
    this.errorMessage,
    this.appleAuthorizationCode,
  });

  const AccountDeletionReauth.verified({String? appleAuthorizationCode})
      : this._(ok: true, appleAuthorizationCode: appleAuthorizationCode);

  const AccountDeletionReauth.cancelled() : this._(ok: false, cancelled: true);

  const AccountDeletionReauth.failed(String message)
      : this._(ok: false, errorMessage: message);

  final bool ok;
  final bool cancelled;
  final String? errorMessage;

  /// Present only after re-authenticating with Sign in with Apple; used to
  /// revoke the user's Apple tokens (App Review 5.1.1(v)).
  final String? appleAuthorizationCode;
}

// ---------------------------------------------------------------------------
// AccountDeletionResult
// ---------------------------------------------------------------------------

class AccountDeletionResult {
  const AccountDeletionResult._({
    required this.success,
    this.errorMessage,
    this.requiresReauth,
  });

  const AccountDeletionResult.success()
      : success        = true,
        errorMessage   = null,
        requiresReauth = false;

  const AccountDeletionResult.failure(String message)
      : success        = false,
        errorMessage   = message,
        requiresReauth = false;

  const AccountDeletionResult.needsReauth()
      : success        = false,
        errorMessage   =
            'Please sign in again before deleting your account.',
        requiresReauth = true;

  final bool    success;
  final String? errorMessage;
  final bool?   requiresReauth;
}

// ---------------------------------------------------------------------------
// AccountDeletionService
//
// Deletion flow:
//
//  1. Get fresh Firebase ID token                  (client, still authed)
//  2. Call Supabase Edge Function delete-user-data (server-side admin)
//       → verifies ID token
//       → hard-deletes users/{uid}     (bypasses allow delete: if false)
//       → hard-deletes owned leagues   (batch)
//       → saves deletion feedback
//  3. Delete Firebase Storage files               (client, still authed)
//  4. Clear local SharedPreferences               (client)
//  5. Hard-delete Firebase Auth account           (client, critical step)
//  6. Sign out                                    (client)
//
// Steps 1–4 run BEFORE step 5 because after user.delete() the Firebase
// auth token is permanently invalidated and no further API calls can
// be authenticated.
// ---------------------------------------------------------------------------

class AccountDeletionService {
  AccountDeletionService._();
  static final AccountDeletionService instance = AccountDeletionService._();

  // Prefixed to avoid collision with supabase_flutter → gotrue User type.
  final firebase_auth.FirebaseAuth _auth    = firebase_auth.FirebaseAuth.instance;
  final FirebaseStorage            _storage = FirebaseStorage.instance;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Re-verifies the signed-in user with the provider they signed up with.
  /// Must be called (and succeed) before [deleteAccount]; it never deletes
  /// or changes anything itself. [requestPassword] is shown only for
  /// email/password accounts and should return null if the user cancels.
  Future<AccountDeletionReauth> reauthenticateForDeletion({
    Future<String?> Function()? requestPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return const AccountDeletionReauth.failed('No signed-in user found.');
    }
    if (user.isAnonymous) return const AccountDeletionReauth.verified();

    final providers = user.providerData.map((p) => p.providerId).toSet();

    try {
      if (providers.contains('apple.com')) {
        final provider = firebase_auth.AppleAuthProvider()..addScope('email');
        final cred = await user.reauthenticateWithProvider(provider);
        return AccountDeletionReauth.verified(
          appleAuthorizationCode: cred.additionalUserInfo?.authorizationCode,
        );
      }

      if (providers.contains('google.com')) {
        final googleSignIn = GoogleSignIn(scopes: ['email']);
        final account = await googleSignIn.signIn();
        if (account == null) return const AccountDeletionReauth.cancelled();
        final auth = await account.authentication;
        await user.reauthenticateWithCredential(
          firebase_auth.GoogleAuthProvider.credential(
            accessToken: auth.accessToken,
            idToken: auth.idToken,
          ),
        );
        return const AccountDeletionReauth.verified();
      }

      if (providers.contains('password')) {
        final email = (user.email ?? '').trim();
        if (email.isEmpty || requestPassword == null) {
          return const AccountDeletionReauth.failed(
            'Please sign in again before deleting your account.',
          );
        }
        final password = await requestPassword();
        if (password == null || password.isEmpty) {
          return const AccountDeletionReauth.cancelled();
        }
        await user.reauthenticateWithCredential(
          firebase_auth.EmailAuthProvider.credential(
            email: email,
            password: password,
          ),
        );
        return const AccountDeletionReauth.verified();
      }

      // Any other provider: fall through to deleteAccount(), which still
      // reports requires-recent-login if Firebase demands it.
      return const AccountDeletionReauth.verified();
    } on firebase_auth.FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'canceled':
        case 'web-context-cancelled':
        case 'popup-closed-by-user':
          return const AccountDeletionReauth.cancelled();
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          return const AccountDeletionReauth.failed(
            'That password is incorrect. Your account was not deleted.',
          );
        case 'user-mismatch':
          return const AccountDeletionReauth.failed(
            'Please choose the same account you signed in with.',
          );
        default:
          return AccountDeletionReauth.failed(
            'We could not verify your identity (${e.code}). '
            'Your account was not deleted.',
          );
      }
    } catch (_) {
      return const AccountDeletionReauth.failed(
        'We could not verify your identity. Your account was not deleted.',
      );
    }
  }

  Future<AccountDeletionResult> deleteAccount({
    String? feedbackReason,
    String? feedbackText,
    String? appleAuthorizationCode,
  }) async {
    final firebase_auth.User? user = _auth.currentUser;

    if (user == null) {
      return const AccountDeletionResult.failure('No signed-in user found.');
    }

    final uid = user.uid.trim();
    if (uid.isEmpty) {
      return const AccountDeletionResult.failure('Invalid user ID.');
    }

    // ── Step 1 + 2: Get ID token → call Edge Function ─────────────────────
    // The Edge Function runs with Firebase service account privileges
    // so it can bypass 'allow delete: if false' on users/{uid}.
    // This MUST happen before user.delete() (step 5).
    final edgeResult = await _callDeleteUserDataEdgeFunction(
      user:           user,
      feedbackReason: feedbackReason,
      feedbackText:   feedbackText,
    );

    if (!edgeResult) {
      // Log the failure but do NOT abort.
      // The user still needs to be able to delete their auth account
      // even if the Firestore cleanup fails (e.g. network issue).
      if (kDebugMode) {
        debugPrint(
          '[AccountDeletionService] Edge function Firestore cleanup '
          'failed — continuing with auth deletion.',
        );
      }
    }

    // ── Step 3: Delete Firebase Storage files ─────────────────────────────
    // Still authenticated here.
    await _deleteStorageFiles(uid);

    // ── Step 4: Clear local SharedPreferences ─────────────────────────────
    await _clearLocalPreferences();

    // ── Step 4b: Revoke Sign in with Apple tokens ─────────────────────────
    // App Review 5.1.1(v) / TN3194. Best-effort: a revocation failure must
    // not leave the user unable to delete their account.
    final appleCode = (appleAuthorizationCode ?? '').trim();
    if (appleCode.isNotEmpty) {
      try {
        await _auth
            .revokeTokenWithAuthorizationCode(appleCode)
            .timeout(const Duration(seconds: 20));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[AccountDeletionService] Apple token revoke failed: $e');
        }
      }
    }

    // ── Step 5: Hard-delete Firebase Auth account (critical) ──────────────
    // After this call the token is permanently invalid.
    // Do NOT call Firestore, Storage, or the Edge Function after this.
    try {
      await user.delete().timeout(const Duration(seconds: 20));
    } on firebase_auth.FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return const AccountDeletionResult.needsReauth();
      }
      return AccountDeletionResult.failure(
        'Failed to delete authentication account: '
        '${e.message ?? e.code}',
      );
    } catch (e) {
      return AccountDeletionResult.failure(
        'Failed to delete authentication account: $e',
      );
    }

    // ── Step 6: Sign out ──────────────────────────────────────────────────
    try {
      await _auth.signOut();
    } catch (_) {}

    return const AccountDeletionResult.success();
  }

  // ── Step 1 + 2: Supabase Edge Function call ────────────────────────────────

  Future<bool> _callDeleteUserDataEdgeFunction({
    required firebase_auth.User user,
    String?                     feedbackReason,
    String?                     feedbackText,
  }) async {
    try {
      // Force-refresh the ID token so it is guaranteed fresh.
      // The Edge Function verifies this against Firebase Auth REST API.
      final idToken = await user
          .getIdToken(true)
          .timeout(const Duration(seconds: 15));

      if (idToken == null || idToken.isEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[AccountDeletionService] Could not obtain Firebase ID token.',
          );
        }
        return false;
      }

      // Build the request body — same pattern as your other functions.
      // firebase_id_token goes in the BODY (not Authorization header)
      // because Supabase rejects non-Supabase JWTs in the header.
      final body = <String, dynamic>{
        'firebase_id_token': idToken,
      };

      if (feedbackReason != null && feedbackReason.trim().isNotEmpty) {
        body['feedbackReason'] = feedbackReason.trim();
      }
      if (feedbackText != null && feedbackText.trim().isNotEmpty) {
        body['feedbackText'] = feedbackText.trim();
      }

      // Call the Supabase Edge Function.
      // supabase_flutter automatically adds the anon key.
      final response = await Supabase.instance.client.functions
          .invoke('delete-user-data', body: body)
          .timeout(const Duration(seconds: 60));

      final data = response.data;

      if (kDebugMode) {
        debugPrint(
          '[AccountDeletionService] Edge function response: $data',
        );
      }

      if (data is Map && data['success'] == true) {
        return true;
      }

      if (kDebugMode) {
        debugPrint(
          '[AccountDeletionService] Edge function returned '
          'unexpected response: $data',
        );
      }
      return false;
    } on FunctionException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[AccountDeletionService] FunctionException: '
          '${e.reasonPhrase} | details: ${e.details}',
        );
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[AccountDeletionService] Edge function call failed: $e',
        );
      }
      return false;
    }
  }

  // ── Step 3: Delete Firebase Storage files ──────────────────────────────────

  Future<void> _deleteStorageFiles(String uid) async {
    final folders = <String>[
      'users/$uid',
      'leagues/$uid',
      'uploads/$uid',
    ];
    for (final folder in folders) {
      await _deleteStorageFolder(folder);
    }
  }

  Future<void> _deleteStorageFolder(String path) async {
    try {
      final result = await _storage
          .ref(path)
          .listAll()
          .timeout(const Duration(seconds: 15));

      for (final item in result.items) {
        try {
          await item.delete().timeout(const Duration(seconds: 10));
        } catch (e) {
          if (kDebugMode) {
            debugPrint(
              '[AccountDeletionService] delete Storage item '
              '${item.fullPath} failed (non-fatal): $e',
            );
          }
        }
      }

      for (final prefix in result.prefixes) {
        try {
          final sub = await prefix
              .listAll()
              .timeout(const Duration(seconds: 10));
          for (final item in sub.items) {
            try {
              await item
                  .delete()
                  .timeout(const Duration(seconds: 10));
            } catch (_) {}
          }
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[AccountDeletionService] _deleteStorageFolder($path) '
          'failed (non-fatal): $e',
        );
      }
    }
  }

  // ── Step 4: Clear local preferences ────────────────────────────────────────

  Future<void> _clearLocalPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));
      await prefs.clear();
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[AccountDeletionService] _clearLocalPreferences '
          'failed (non-fatal): $e',
        );
      }
    }
  }
}
