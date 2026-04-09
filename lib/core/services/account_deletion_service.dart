import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  final FirebaseAuth    _auth    = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<AccountDeletionResult> deleteAccount({
    String? feedbackReason,
    String? feedbackText,
  }) async {
    final user = _auth.currentUser;
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
      // Any un-deleted Firestore docs will be orphaned but harmless
      // since the auth account (the identity) is gone.
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

    // ── Step 5: Hard-delete Firebase Auth account (critical) ──────────────
    // After this call the token is permanently invalid.
    // Do NOT call Firestore, Storage, or the Edge Function after this.
    try {
      await user.delete().timeout(const Duration(seconds: 20));
    } on FirebaseAuthException catch (e) {
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

  // ── Step 1 + 2: Supabase Edge Function ────────────────────────────────────

  Future<bool> _callDeleteUserDataEdgeFunction({
    required User user,
    String?       feedbackReason,
    String?       feedbackText,
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
              await item.delete().timeout(const Duration(seconds: 10));
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
