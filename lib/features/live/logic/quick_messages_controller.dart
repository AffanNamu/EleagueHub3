import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/user_profile_repository.dart';
import '../../verification/logic/badge_providers.dart';
import 'quick_message_policy.dart';

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository();
});

// FIXED: this used to read PreferencesService.getCurrentUserId(), which is
// permanently hardcoded to return null (see prefs_service.dart's
// online-only storage policy) -- so every provider below always saw an
// empty uid, and every QuickMessagesController write threw "Missing user
// id". Reads from FirebaseAuth directly instead, matching every other
// current-user provider in the app.
final currentUserIdProvider = Provider<String>((ref) {
  return FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
});

/// Premium flag comes from Firestore: users/{uid}.isPremium
///
/// Derived from the app-wide currentUserProfileProvider's own stream
/// rather than opening a second users/{uid} Firestore listener.
final isPremiumProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid.trim().isEmpty) return Stream<bool>.value(false);
  return ref
      .watch(currentUserProfileProvider.stream)
      .map((profile) => profile?.premiumActive ?? false);
});

/// Firestore list: users/{uid}.quickMessagesCustom
final customQuickMessagesProvider = StreamProvider<List<String>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid.trim().isEmpty) return Stream<List<String>>.value(const <String>[]);
  return ref
      .watch(currentUserProfileProvider.stream)
      .map((profile) => profile?.quickMessagesCustom ?? const <String>[]);
});

/// Overlay list (localized defaults + premium custom). This is the list we
/// push to the Android overlay (a native surface with no BuildContext of its
/// own), so the caller must supply the already-localized default messages —
/// see `_localizedDefaultQuickMessages` in call_room_screen.dart, which
/// reuses the same translation keys as the in-app quick message picker.
/// Falls back to [QuickMessagePolicy.defaultFallback] (English) if the
/// caller passes an empty list.
final overlayQuickMessagesProvider =
    Provider.family<List<String>, List<String>>((ref, defaultMessages) {
  final premium = ref.watch(isPremiumProvider).value ?? false;
  final custom = ref.watch(customQuickMessagesProvider).value ?? const <String>[];

  final effectiveCustom = premium ? QuickMessagePolicy.sanitizeList(custom) : const <String>[];
  final combined = <String>[
    ...(defaultMessages.isNotEmpty
        ? defaultMessages
        : QuickMessagePolicy.defaultFallback),
    ...effectiveCustom,
  ];

  // Ensure unique and safe length.
  final seen = <String>{};
  final out = <String>[];
  for (final m in combined) {
    final v = QuickMessagePolicy.normalize(m);
    if (v.isEmpty) continue;
    if (seen.add(v.toLowerCase())) out.add(v);
  }
  return out;
});

/// In-app custom messages (premium gated). UI can use this to show/edit.
final inAppCustomQuickMessagesProvider = Provider<List<String>>((ref) {
  final premium = ref.watch(isPremiumProvider).value ?? false;
  if (!premium) return const <String>[];
  final custom = ref.watch(customQuickMessagesProvider).value ?? const <String>[];
  return QuickMessagePolicy.sanitizeList(custom);
});

final quickMessagesControllerProvider = Provider<QuickMessagesController>((ref) {
  return QuickMessagesController(ref);
});

// NOTE (i18n): Exception messages thrown below ('Missing user id',
// 'Premium required', 'Max N messages', and QuickMessagePolicy's
// validation errors) are surfaced verbatim by
// lib/features/profile/presentation/settings_screen.dart (outside this
// localization pass's file list) via `e.toString()`. Localizing them
// properly requires that caller to map an error code to translated text,
// which is a larger cross-file refactor than this pass covers, so they
// are left as English for now.
class QuickMessagesController {
  QuickMessagesController(this._ref);

  final Ref _ref;

  String get _uid => _ref.read(currentUserIdProvider);

  UserProfileRepository get _repo => _ref.read(userProfileRepositoryProvider);

  Future<bool> get _isPremium async {
    // Best-effort: read latest snapshot once.
    final uid = _uid.trim();
    if (uid.isEmpty) return false;
    final p = await _repo.fetchByUserId(uid);
    return p?.isPremium == true;
  }

  Future<List<String>> _loadCustom() async {
    final uid = _uid.trim();
    if (uid.isEmpty) return const <String>[];
    final p = await _repo.fetchByUserId(uid);
    return QuickMessagePolicy.sanitizeList(p?.quickMessagesCustom ?? const <String>[]);
  }

  Future<void> addCustomMessage(String raw) async {
    final uid = _uid.trim();
    if (uid.isEmpty) throw Exception('Missing user id');

    if (!await _isPremium) {
      throw Exception('Premium required');
    }

    final res = QuickMessagePolicy.validateCustomMessage(raw);
    if (!res.ok) throw Exception(res.error);

    final current = await _loadCustom();
    if (current.length >= QuickMessagePolicy.maxCustomCount) {
      throw Exception('Max ${QuickMessagePolicy.maxCustomCount} messages');
    }

    // Prevent duplicates (case-insensitive)
    final next = <String>[...current];
    if (next.any((e) => e.toLowerCase() == res.value.toLowerCase())) return;

    next.add(res.value);
    await _repo.updateQuickMessagesCustom(userId: uid, messages: next);
  }

  Future<void> deleteCustomMessageAt(int index) async {
    final uid = _uid.trim();
    if (uid.isEmpty) throw Exception('Missing user id');

    if (!await _isPremium) {
      throw Exception('Premium required');
    }

    final current = await _loadCustom();
    if (index < 0 || index >= current.length) return;

    final next = <String>[...current]..removeAt(index);
    await _repo.updateQuickMessagesCustom(userId: uid, messages: next);
  }

  Future<void> reorderCustom(int oldIndex, int newIndex) async {
    final uid = _uid.trim();
    if (uid.isEmpty) throw Exception('Missing user id');

    if (!await _isPremium) {
      throw Exception('Premium required');
    }

    final current = await _loadCustom();
    if (oldIndex < 0 || oldIndex >= current.length) return;

    var ni = newIndex;
    if (ni < 0) ni = 0;
    if (ni >= current.length) ni = current.length - 1;

    final next = <String>[...current];
    final item = next.removeAt(oldIndex);
    next.insert(ni, item);

    await _repo.updateQuickMessagesCustom(userId: uid, messages: next);
  }

  Future<void> replaceAllCustom(List<String> raw) async {
    final uid = _uid.trim();
    if (uid.isEmpty) throw Exception('Missing user id');

    if (!await _isPremium) {
      throw Exception('Premium required');
    }

    // Validate each message; stop at first error.
    final next = <String>[];
    for (final r in raw) {
      final res = QuickMessagePolicy.validateCustomMessage(r);
      if (!res.ok) throw Exception(res.error);
      if (next.any((e) => e.toLowerCase() == res.value.toLowerCase())) continue;
      next.add(res.value);
      if (next.length >= QuickMessagePolicy.maxCustomCount) break;
    }

    await _repo.updateQuickMessagesCustom(userId: uid, messages: next);
  }
}
