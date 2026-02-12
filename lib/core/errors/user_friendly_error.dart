import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/services.dart';

/// Centralized user-friendly error mapping.
///
/// ONLINE-ONLY UX RULE:
/// - Never show raw Firebase/technical errors to users.
/// - Always map known exception types to clean messages.
///
/// Note: Multiple features define their own `UserFriendlyException` classes.
/// This mapper will only trust `.message` if the runtimeType contains
/// "UserFriendly" to avoid leaking technical messages.
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

    // Trust only explicitly user-friendly exceptions.
    final typeName = error.runtimeType.toString();
    if (typeName.contains('UserFriendly')) {
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

    return 'Something went wrong. Please try again.';
  }
}
