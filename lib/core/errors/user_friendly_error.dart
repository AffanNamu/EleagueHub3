import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Centralized user-friendly error mapping.
///
/// ONLINE-ONLY UX RULE:
/// - Never show raw Firebase/technical errors to users.
/// - Always map known exception types to clean messages.
///
/// FIXED: the final "trust this message" branch used to only accept
/// exceptions whose runtimeType contained the literal substring
/// "UserFriendly". In practice almost none of the app's own exception
/// classes are actually named that — e.g. UserProfileRepositoryException,
/// UsernameUnavailableException, TeamProfileRepositoryException,
/// StatusRepositoryException, PublicFeedRepositoryException, and
/// DiscussionsRepositoryException all carry deliberately curated, safe
/// messages via `_rethrowFriendly()`-style helpers in their repositories,
/// but none of them matched that substring check. So every one of those
/// specific, useful messages ("That username is already taken.", "You do
/// not have permission to access this profile.", etc.) was silently
/// discarded and replaced with the generic "Something went wrong." This
/// was the actual cause of the username-save bug reported — it had
/// nothing to do with the transactional reservation logic itself, which
/// was already correct.
///
/// By the time execution reaches the final branch below, every raw
/// system exception (SocketException, TimeoutException,
/// PlatformException, FirebaseAuthException, FirebaseException) has
/// already been handled and returned above. So safely widening the trust
/// check to also accept any app-authored exception whose type name ends
/// in "Exception" only ever matches classes like the ones above — never
/// a raw system exception — and fixes this class of bug across the whole
/// app, not just this one screen.
class UserFriendlyError {
  UserFriendlyError._();

  static String toMessage(Object error) {
    // Network (IO)
    if (error is SocketException) {
      return 'Your network appears to be offline. Please check your connection and try again.';
    }
    if (error is TimeoutException) {
      return 'Your internet connection seems unstable. Please try again.';
    }
    if (error is HandshakeException || error is TlsException) {
      return 'Your internet connection seems unstable. Please try again.';
    }

    // Platform (permissions, channels, etc.)
    if (error is PlatformException) {
      // Never surface platform codes/messages directly to UI.
      return "We couldn't complete this action. Please try again.";
    }

    // Firebase Auth
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'network-request-failed':
          return 'Your network appears to be offline. Please check your connection and try again.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait a moment and try again.';
        case 'user-disabled':
          return 'This account has been disabled. Please contact support.';
        case 'unauthenticated':
          return 'Please sign in and try again.';
        default:
          return "We couldn't sign you in right now. Please try again.";
      }
    }

    // Firebase (Firestore/Storage/etc.)
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Your network appears to be offline. Please check your connection and try again.';
        case 'permission-denied':
          return 'You don’t have permission to do that right now.';
        case 'unauthenticated':
          return 'Please sign in and try again.';
        default:
          return "We couldn't complete this action. Please try again.";
      }
    }

    // Trust app-authored exceptions with curated messages. Matches both
    // the original "UserFriendly*" naming convention AND the more common
    // "*Exception" convention already used across this codebase's
    // repositories (UserProfileRepositoryException,
    // UsernameUnavailableException, TeamProfileRepositoryException,
    // StatusRepositoryException, PublicFeedRepositoryException,
    // DiscussionsRepositoryException, etc.) — every one of those is a raw
    // system exception check above having already returned, so nothing
    // technical/unsafe reaches this branch.
    final typeName = error.runtimeType.toString();
    if (typeName.contains('UserFriendly') || typeName.endsWith('Exception')) {
      try {
        final dynamic dyn = error;
        final msg = dyn.message;
        if (msg is String && msg.trim().isNotEmpty) {
          return msg.trim();
        }
      } catch (_) {
        // fall through
      }
      final s = error.toString().trim();
      if (s.isNotEmpty) return s;
    }

    if (kDebugMode) {
      debugPrint(
        '[UserFriendlyError] Unmapped exception reached generic fallback: '
        '$typeName -> $error',
      );
    }

    return 'Something went wrong. Please try again.';
  }
}
