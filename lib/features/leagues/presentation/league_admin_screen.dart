import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../../../core/services/sync_trigger.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../data/league_announcements_local.dart';
import '../data/league_spaces_local.dart';
import '../data/leagues_repository_local.dart';
import '../logic/coupon_codes_service.dart';
import '../logic/coupon_config_service.dart';
import '../logic/league_creation_payment_service.dart';
import '../logic/league_media_service.dart';
import '../models/league.dart';
import '../models/league_announcement.dart';
import '../models/league_format.dart';
import '../models/league_space.dart';
import '../models/team.dart';
import '../utils/current_user.dart';
import 'add_teams_screen.dart';
import 'league_participants_screen.dart';
import 'utils/roster_csv_exporter.dart';

class LeagueAdminScreen extends ConsumerStatefulWidget {
  final bool hasPendingChanges;
  final String leagueId;

  const LeagueAdminScreen({
    super.key,
    this.hasPendingChanges = true,
    required this.leagueId,
  });

  @override
  ConsumerState<LeagueAdminScreen> createState() => _LeagueAdminScreenState();
}

class _LeagueAdminScreenState extends ConsumerState<LeagueAdminScreen> {
  late LocalLeaguesRepository _localRepo;
  late LeagueAnnouncementsFirebase _annRepo;
  late LeagueSpacesFirebase _spaceRepo;

  League? _league;
  LeagueSpace? _space;

  bool _isLeagueLoading = true;
  bool _isSyncing = false;
  bool _exportingRoster = false;

  bool _showAddMeAsParticipant = false;
  bool _addingMeAsParticipant = false;

  bool _processingUpgradePayment = false;

  /// Legacy/local user id (may be a shareId in older deployments).
  /// NOTE: CurrentUser.getUserId() now returns Firebase uid, but we keep this field
  /// name for backward compatibility with older local storage.
  String _currentUserId = '';

  /// Firebase Auth UID (required by Firestore rules for coupons/codes).
  String _currentAuthUid = '';

  /// Remote, rules-authoritative organizer/owner UIDs from Firestore league doc.
  /// Used to ensure coupon admin UI matches server-side rules (Firebase UID only).
  String _remoteOrganizerUid = '';
  String _remoteOwnerUid = '';

  final Uuid _uuid = const Uuid();

  static const List<String> _groupNames = <String>[
    'Group A',
    'Group B',
    'Group C',
    'Group D',
    'Group E',
    'Group F',
    'Group G',
    'Group H',
  ];

  bool _looksLikeFirebaseUid(String s) => s.trim().length > 20;

  /// Rules-authoritative owner detection (Firebase UID only).
  /// Prefer remote organizerUid/ownerUid. Fall back to league.organizerUid if present.
  /// Last resort: legacy organizerUserId ONLY if it *looks like* a Firebase UID.
  bool _isRulesOwnerForLeague(
    League league, {
    required String authUid,
    required String remoteOrganizerUid,
    required String remoteOwnerUid,
  }) {
    final a = authUid.trim();
    if (a.isEmpty) return false;

    final ro = remoteOrganizerUid.trim();
    final rw = remoteOwnerUid.trim();
    if (ro.isNotEmpty || rw.isNotEmpty) {
      return ro == a || rw == a;
    }

    final ou = league.organizerUid.trim();
    if (ou.isNotEmpty) return ou == a;

    final legacy = league.organizerUserId.trim();
    return _looksLikeFirebaseUid(legacy) && legacy == a;
  }

  /// Coupon admin permission must match Firestore rules.
  /// Firebase UID is the ONLY authority; short/share IDs are display-only.
  ///
  /// IMPORTANT:
  /// - We require remote organizerUid/ownerUid to be loaded (from Firestore) before enabling coupon admin UI.
  /// - If remote ids are unknown (offline/denied), the UI will not pretend you can manage coupons.
  bool _canManageCoupons(League league) {
    final auth = _currentAuthUid.trim();
    if (auth.isEmpty) return false;

    final ro = _remoteOrganizerUid.trim();
    final rw = _remoteOwnerUid.trim();

    // If we know remote owner ids, trust them (matches Firestore rules).
    if (ro.isNotEmpty || rw.isNotEmpty) {
      return ro == auth || rw == auth;
    }

    // OFFLINE / UNSYNCED fallback:
    // Use local organizerUid ONLY if it matches the current auth uid.
    final localOrgUid = league.organizerUid.trim();
    if (localOrgUid.isNotEmpty && localOrgUid == auth) return true;

    // Backward compat ONLY if organizerUserId actually stores Firebase UID.
    final legacy = league.organizerUserId.trim();
    return _looksLikeFirebaseUid(legacy) && legacy == auth;
  }
