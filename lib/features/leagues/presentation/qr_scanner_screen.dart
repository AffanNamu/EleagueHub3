import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:eleaguehub3/core/errors/user_friendly_error.dart';
import 'package:eleaguehub3/features/leagues/logic/league_charges_payment_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/league_flip_card.dart';
import '../data/leagues_repository_local.dart';
import '../models/enums.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import '../models/membership.dart';

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});

  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> with WidgetsBindingObserver {
  static const Color _premiumAmber = Color(0xFFF59E0B);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isScanned = false;

  League? _joinedLeague;
  bool _joining = false;
  String? _error;

  late final MobileScannerController _scannerController;

  bool _torchOn = false;
  CameraFacing _facing = CameraFacing.back;

  /// Firebase Auth UID (required by Firestore rules for memberships/coupons).
  String _authUid = '';

  bool _chargesPaid = false;

  LeagueJoinMode? _joinedMode;

  /// Used to show a friendly message, e.g. when league is full and user is downgraded to viewer,
  /// or when the user was already added by admin.
  String? _joinNotice;

  bool _permissionChecked = false;
  bool _cameraPermissionGranted = false;
  bool _requestingPermission = false;
  bool _scannerStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: _facing,
      torchEnabled: false,
      autoStart: false,
    );

    // ignore: discarded_futures
    _initScanner();
  }

  Future<void> _initScanner() async {
    await _ensureCameraPermission(startScannerIfGranted: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_joinedLeague != null) return;

    if (state == AppLifecycleState.resumed) {
      // Re-check permission when user returns from system settings
      // ignore: discarded_futures
      _ensureCameraPermission(startScannerIfGranted: true);
    } else if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (_scannerStarted) {
        // ignore: discarded_futures
        _scannerController.stop();
        _scannerStarted = false;
      }
    }
  }

  void _setError(String? msg) {
    if (!mounted) return;
    setState(() => _error = msg);
  }

  Future<void> _ensureCameraPermission({required bool startScannerIfGranted}) async {
    final status = await Permission.camera.status;
    final granted = status.isGranted;

    if (!mounted) return;
    setState(() {
      _permissionChecked = true;
      _cameraPermissionGranted = granted;
    });

    if (startScannerIfGranted && granted) {
      await _startScannerSafely();
    } else {
      await _stopScannerSafely();
    }
  }

  Future<void> _requestCameraPermission() async {
    if (_requestingPermission) return;

    setState(() {
      _requestingPermission = true;
      _error = null;
    });

    try {
      final result = await Permission.camera.request();
      final granted = result.isGranted;

      if (!mounted) return;
      setState(() {
        _permissionChecked = true;
        _cameraPermissionGranted = granted;
        _requestingPermission = false;
      });

      if (granted) {
        await _startScannerSafely();
      } else {
        await _stopScannerSafely();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _requestingPermission = false);
      _setError(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }

  Future<void> _startScannerSafely() async {
    if (_scannerStarted) return;
    try {
      await _scannerController.start();
      _scannerStarted = true;
    } catch (e) {
      _scannerStarted = false;
      _setError('We couldn’t access your camera. Please try again.');
    }
  }

  Future<void> _stopScannerSafely() async {
    if (!_scannerStarted) return;
    try {
      await _scannerController.stop();
    } catch (_) {}
    _scannerStarted = false;
  }

  Future<LeagueJoinMode?> _promptJoinMode(BuildContext context, {required String joinCode}) async {
    return showModalBottomSheet<LeagueJoinMode>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final l10n = ctx.l10n;
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Glass(
                  borderRadius: 28,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.tr('qr_scanner_join_mode_title'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${l10n.tr('qr_scanner_join_code_prefix')}${joinCode.toUpperCase()}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withOpacity(0.70),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        _JoinModeTile(
                          title: l10n.tr('qr_scanner_join_mode_participant_title'),
                          subtitle: l10n.tr('qr_scanner_join_mode_participant_subtitle'),
                          icon: Icons.sports_esports,
                          accent: cs.primary,
                          onTap: () => Navigator.of(ctx).pop(LeagueJoinMode.participant),
                        ),
                        const SizedBox(height: 10),
                        _JoinModeTile(
                          title: l10n.tr('qr_scanner_join_mode_viewer_title'),
                          subtitle: l10n.tr('qr_scanner_join_mode_viewer_subtitle'),
                          icon: Icons.visibility,
                          accent: cs.onSurface.withOpacity(0.72),
                          onTap: () => Navigator.of(ctx).pop(LeagueJoinMode.viewer),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(null),
                          child: Text(l10n.tr('common_cancel')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _requiresCharges(League league) {
    return league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;
  }

  bool _isCreator(League league, {required String authUid}) {
    final orgUid = league.organizerUid.trim();
    return authUid.trim().isNotEmpty && orgUid.isNotEmpty && orgUid == authUid.trim();
  }

  Future<bool> _hasPaidChargesRemote({
    required String userId,
    required String leagueId,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return false;

    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('leagueCharges')
        .doc(leagueId)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 8));

    if (!doc.exists) return false;
    final data = doc.data() ?? <String, dynamic>{};
    return data['paid'] == true;
  }

  Future<void> _storePaidChargesRemote({
    required String userId,
    required String leagueId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;

    await _firestore
        .collection('users')
        .doc(uid)
        .collection('leagueCharges')
        .doc(leagueId)
        .set(
          {
            'paid': true,
            'leagueId': leagueId,
            'userId': uid,
            'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
            ...payload,
          },
          SetOptions(merge: true),
        )
        .timeout(const Duration(seconds: 12));
  }

  Future<void> _handleScan(String payload) async {
    if (_joining) return;

    final l10n = context.l10n;

    final parsed = _parseJoinPayload(payload);
    if (parsed == null) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = l10n.tr('qr_scanner_invalid_qr_join_code');
        _isScanned = false;
      });
      await _startScannerSafely();
      return;
    }

    final joinCode = parsed.code;

    final selectedMode = await _promptJoinMode(context, joinCode: joinCode);
    if (selectedMode == null) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = null;
        _isScanned = false;
      });
      await _startScannerSafely();
      return;
    }

    setState(() {
      _joining = true;
      _error = null;
      _joinNotice = null;
    });

    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    _authUid = authUid;

    if (authUid.isEmpty) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Please sign in and try again.';
        _isScanned = false;
      });
      await _startScannerSafely();
      return;
    }

    final repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));

    try {
      final league = await repo
          .joinLeagueLocallyByCode(
            joinCode: joinCode,
            userId: authUid,
            mode: selectedMode,
            placeholderBuilder: (generatedLeagueId) {
              // Online-only: placeholder is ignored by repo, but keep signature.
              final now = DateTime.now().millisecondsSinceEpoch;
              return League(
                id: generatedLeagueId,
                name: l10n.tr('qr_scanner_joined_league_placeholder_name'),
                format: LeagueFormat.classic,
                privacy: LeaguePrivacy.private,
                region: 'Global',
                maxTeams: 20,
                season: '2026',
                organizerUid: '',
                organizerUserId: '',
                code: joinCode,
                qrPayloadOverride: '',
                settings: LeagueSettings.defaultsFor(LeagueFormat.classic).copyWith(lastPulledAtMs: now),
                updatedAtMs: now,
                version: 1,
              );
            },
          )
          .timeout(const Duration(seconds: 25));

      final Membership? membership =
          await repo.getMembership(leagueId: league.id, userId: authUid).timeout(const Duration(seconds: 15));
      final effectiveMode = (membership != null) ? LeagueJoinMode.participant : LeagueJoinMode.viewer;

      String? notice;
      final bool adminAlreadyAdded = membership != null && (membership.teamId?.trim().isNotEmpty == true);

      if (adminAlreadyAdded) {
        notice = (selectedMode == LeagueJoinMode.viewer)
            ? l10n.tr('qr_scanner_notice_viewer_but_already_added_team_assigned')
            : l10n.tr('qr_scanner_notice_already_added_team_assigned');
      } else if (membership != null) {
        notice = (selectedMode == LeagueJoinMode.viewer)
            ? l10n.tr('qr_scanner_notice_viewer_but_already_registered_participant')
            : l10n.tr('qr_scanner_notice_already_registered');
      } else if (selectedMode == LeagueJoinMode.participant && effectiveMode == LeagueJoinMode.viewer) {
        notice = l10n.tr('qr_scanner_notice_league_full_joined_viewer_only');
      } else if (selectedMode == LeagueJoinMode.viewer) {
        notice = l10n.tr('qr_scanner_notice_joined_viewer_only');
      }

      final paid = await _hasPaidChargesRemote(userId: authUid, leagueId: league.id);

      if (!mounted) return;

      setState(() {
        _joinedLeague = league;
        _joining = false;
        _chargesPaid = paid;
        _joinedMode = effectiveMode;
        _joinNotice = notice;
      });

      await _maybePromptChargesAfterJoin(
        context,
        joinedLeague: league,
        authUid: authUid,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
        _isScanned = false;
      });
      await _startScannerSafely();
    }
  }

  Future<void> _maybePromptChargesAfterJoin(
    BuildContext context, {
    required League joinedLeague,
    required String authUid,
  }) async {
    final l10n = context.l10n;

    if (!_requiresCharges(joinedLeague)) return;
    if (_isCreator(joinedLeague, authUid: authUid)) return;

    final alreadyPaid = await _hasPaidChargesRemote(userId: authUid, leagueId: joinedLeague.id);
    if (alreadyPaid) {
      if (!mounted) return;
      setState(() => _chargesPaid = true);
      return;
    }

    final shouldPay = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final dialogTheme = Theme.of(ctx);
        final dialogCs = dialogTheme.colorScheme;

        return AlertDialog(
          backgroundColor: dialogCs.surface,
          title: Text(
            l10n.tr('qr_scanner_unlock_dialog_title'),
            style: TextStyle(color: dialogCs.onSurface, fontWeight: FontWeight.w900),
          ),
          content: Text(
            '${l10n.tr('qr_scanner_unlock_dialog_content_prefix')}${joinedLeague.name}${l10n.tr('qr_scanner_unlock_dialog_content_suffix')}',
            style: TextStyle(color: dialogCs.onSurface.withOpacity(0.72), height: 1.35, fontWeight: FontWeight.w600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.tr('common_later')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.tr('common_pay_now')),
            ),
          ],
        );
      },
    );

    if (shouldPay != true) return;

    await _unlockNow(context, league: joinedLeague, authUid: authUid);
  }

  Future<void> _unlockNow(
    BuildContext context, {
    required League league,
    required String authUid,
  }) async {
    final l10n = context.l10n;

    final alreadyPaid = await _hasPaidChargesRemote(userId: authUid, leagueId: league.id);
    if (alreadyPaid) {
      if (!mounted) return;
      setState(() => _chargesPaid = true);
      return;
    }

    setState(() {
      _joining = true;
      _error = null;
    });

    try {
      final paymentService = ref.read(leagueChargesPaymentServiceProvider);

      final result = await paymentService
          .payLeagueCharges(
            context: context,
            userId: authUid,
            leagueId: league.id,
            leagueName: league.name,
          )
          .timeout(const Duration(seconds: 60));

      if (!mounted) return;

      if (!result.success) {
        setState(() {
          _joining = false;
          _error = result.errorMessage ?? l10n.tr('qr_scanner_payment_failed');
        });
        return;
      }

      await _storePaidChargesRemote(
        userId: authUid,
        leagueId: league.id,
        payload: <String, dynamic>{
          'receiptId': result.receiptId ?? '',
          'provider': result.provider,
          'paidAtMs': result.paidAtMs,
        },
      );

      if (!mounted) return;
      setState(() {
        _joining = false;
        _chargesPaid = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_access_charges_paid_success')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_cameraPermissionGranted) return;
    if (_isScanned || _joining) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;

    _isScanned = true;
    // ignore: discarded_futures
    _scannerController.stop();
    _scannerStarted = false;

    // ignore: discarded_futures
    _handleScan(raw);
  }

  Future<void> _showManualEntrySheet() async {
    final controller = TextEditingController();

    try {
      final code = await showModalBottomSheet<String?>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (ctx) {
          final l10n = ctx.l10n;
          final theme = Theme.of(ctx);
          final cs = theme.colorScheme;

          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset).add(const EdgeInsets.all(12)),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Glass(
                    borderRadius: 28,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.tr('qr_scanner_manual_entry_title'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.tr('qr_scanner_manual_entry_subtitle'),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.70),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: controller,
                            autofocus: true,
                            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800),
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: l10n.tr('qr_scanner_join_code_hint'),
                              prefixIcon: const Icon(Icons.key),
                              suffixIcon: IconButton(
                                tooltip: l10n.tr('common_paste'),
                                icon: Icon(Icons.content_paste, color: cs.primary),
                                onPressed: () async {
                                  final data = await Clipboard.getData('text/plain');
                                  final text = data?.text ?? '';
                                  if (text.trim().isEmpty) return;
                                  controller.text = text.trim();
                                  controller.selection = TextSelection.fromPosition(
                                    TextPosition(offset: controller.text.length),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(null),
                                  child: Text(l10n.tr('common_cancel')),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                                  icon: const Icon(Icons.login),
                                  label: Text(l10n.tr('common_continue')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );

      if (!mounted) return;

      if (code == null || code.trim().isEmpty) return;

      await _stopScannerSafely();
      setState(() {
        _isScanned = true;
      });

      await _handleScan(code);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _error = null;
      _isScanned = false;
      _joining = false;
    });
    await _ensureCameraPermission(startScannerIfGranted: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_joinedLeague != null) {
      final league = _joinedLeague!;
      final screenWidth = MediaQuery.of(context).size.width;
      final isWide = screenWidth > 600;

      final requiresCharges = _requiresCharges(league);
      final isCreator = _isCreator(league, authUid: _authUid);
      final showUnlock = requiresCharges && !isCreator && !_chargesPaid;

      final mode = _joinedMode;
      final joinedLine = (mode == LeagueJoinMode.viewer)
          ? l10n.tr('qr_scanner_joined_line_viewer')
          : l10n.tr('qr_scanner_joined_line_participant');

      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('qr_scanner_joined_appbar_title')),
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.go('/leagues'),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 600 : 450),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LeagueFlipCard(
                      leagueName: league.name,
                      leagueCode: league.code,
                      distribution: '${context.l10n.tr(league.format.l10nKey)} • ${league.season}',
                      subtitle: '0 / ${league.maxTeams} ${l10n.tr('qr_scanner_teams_suffix')}',
                      onDoubleTap: () => context.push('/leagues/${league.id}'),
                      qrWidget: QrImageView(
                        data: league.qrPayload,
                        version: QrVersions.auto,
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
                    const SizedBox(height: 16),
                    Glass(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            joinedLine,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.86),
                              height: 1.4,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (_joinNotice != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _joinNotice!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: _premiumAmber,
                                fontWeight: FontWeight.w900,
                                height: 1.35,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            showUnlock
                                ? l10n.tr('qr_scanner_requires_charges_message')
                                : l10n.tr('qr_scanner_can_open_league_message'),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.72),
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (showUnlock) ...[
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _joining ? null : () => _unlockNow(context, league: league, authUid: _authUid),
                                icon: _joining
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.lock_open),
                                label: Text(l10n.tr('qr_scanner_unlock_now').toUpperCase()),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => context.go('/leagues'),
                                  child: Text(l10n.tr('common_done').toUpperCase()),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => context.push('/leagues/${league.id}'),
                                  child: Text(l10n.tr('common_open').toUpperCase()),
                                ),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: cs.error, fontWeight: FontWeight.w900),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _scannerController,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) {
                final theme = Theme.of(context);
                final cs = theme.colorScheme;

                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Glass(
                      padding: const EdgeInsets.all(16),
                      borderRadius: 22,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt_outlined, color: cs.onSurface.withOpacity(0.72), size: 34),
                          const SizedBox(height: 10),
                          Text(
                            context.l10n.tr('qr_scanner_camera_not_available'),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Please check your camera permission and try again.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withOpacity(0.70),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () async {
                                    setState(() {
                                      _error = null;
                                      _isScanned = false;
                                    });
                                    await _ensureCameraPermission(startScannerIfGranted: true);
                                  },
                                  child: Text(context.l10n.tr('common_retry')),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _joining ? null : _showManualEntrySheet,
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: cs.onSurface.withOpacity(0.18)),
                                    foregroundColor: cs.primary,
                                  ),
                                  child: Text(context.l10n.tr('qr_scanner_enter_code_instead')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ScannerOverlayPainter(
                  accent: cs.primary,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 26),
                        onPressed: () => context.pop(),
                      ),
                      const Spacer(),
                      if (_joining)
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: cs.primary),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: (!_cameraPermissionGranted && _permissionChecked)
                            ? Glass(
                                key: const ValueKey('permission_card'),
                                padding: const EdgeInsets.all(14),
                                borderRadius: 24,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      l10n.tr('qr_scanner_allow_camera_access_title'),
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        color: cs.onSurface,
                                        fontWeight: FontWeight.w900,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      l10n.tr('qr_scanner_allow_camera_access_description'),
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: cs.onSurface.withOpacity(0.72),
                                        height: 1.35,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _requestingPermission ? null : () => openAppSettings(),
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(color: cs.onSurface.withOpacity(0.18)),
                                              foregroundColor: cs.onSurface.withOpacity(0.80),
                                            ),
                                            child: Text(l10n.tr('qr_scanner_open_settings')),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: _requestingPermission ? null : _requestCameraPermission,
                                            child: _requestingPermission
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                                  )
                                                : Text(l10n.tr('qr_scanner_grant_permission')),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton(
                                        onPressed: _joining ? null : _showManualEntrySheet,
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: cs.onSurface.withOpacity(0.18)),
                                          foregroundColor: cs.primary,
                                        ),
                                        child: Text(l10n.tr('qr_scanner_enter_code_instead').toUpperCase()),
                                      ),
                                    ),
                                    if (_error != null) ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: cs.error,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            : Glass(
                                key: const ValueKey('controls_card'),
                                padding: const EdgeInsets.all(14),
                                borderRadius: 24,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      l10n.tr('qr_scanner_center_qr_instruction'),
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: cs.onSurface.withOpacity(0.72),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        height: 1.3,
                                      ),
                                    ),
                                    if (_error != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        _error!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: cs.error,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: FilledButton.icon(
                                            onPressed: _joining ? null : _showManualEntrySheet,
                                            icon: const Icon(Icons.key),
                                            label: Text(l10n.tr('qr_scanner_enter_code').toUpperCase()),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _joining ? null : _scanAgain,
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(color: cs.onSurface.withOpacity(0.18)),
                                              foregroundColor: cs.primary,
                                            ),
                                            child: Text(l10n.tr('qr_scanner_scan_again').toUpperCase()),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          tooltip: _torchOn
                                              ? l10n.tr('qr_scanner_torch_off_tooltip')
                                              : l10n.tr('qr_scanner_torch_on_tooltip'),
                                          icon: Icon(
                                            _torchOn ? Icons.flash_on : Icons.flash_off,
                                            color: Colors.white,
                                          ),
                                          onPressed: !_cameraPermissionGranted || _joining
                                              ? null
                                              : () async {
                                                  await _scannerController.toggleTorch();
                                                  setState(() => _torchOn = !_torchOn);
                                                },
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          tooltip: l10n.tr('qr_scanner_switch_camera_tooltip'),
                                          icon: const Icon(Icons.cameraswitch, color: Colors.white),
                                          onPressed: !_cameraPermissionGranted || _joining
                                              ? null
                                              : () async {
                                                  final newFacing = _facing == CameraFacing.back
                                                      ? CameraFacing.front
                                                      : CameraFacing.back;
                                                  await _scannerController.switchCamera();
                                                  setState(() => _facing = newFacing);
                                                },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                      ),
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

  _JoinParse? _parseJoinPayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('eleaguehub://')) {
      try {
        final uri = Uri.parse(trimmed);
        final code = uri.queryParameters['code']?.trim();
        if (code == null || code.isEmpty) return null;
        return _JoinParse(code: code.toUpperCase());
      } catch (_) {
        return null;
      }
    }

    final code = trimmed.toUpperCase();
    final ok = RegExp(r'^[A-Z0-9]{4,16}$').hasMatch(code);
    if (!ok) return null;

    return _JoinParse(code: code);
  }
}

class _JoinParse {
  final String code;
  const _JoinParse({required this.code});
}

class _JoinModeTile extends StatelessWidget {
  const _JoinModeTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Glass(
      borderRadius: 20,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withOpacity(0.18),
          child: Icon(icon, color: accent),
        ),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withOpacity(0.70),
            fontSize: 12,
            height: 1.25,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Icon(isRtl ? Icons.chevron_left : Icons.chevron_right, color: cs.onSurface.withOpacity(0.35)),
        onTap: onTap,
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Color accent;

  const _ScannerOverlayPainter({
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.55);

    canvas.drawRect(Offset.zero & size, overlayPaint);

    final cutOutSize = size.shortestSide * 0.62;
    final cutOutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cutOutSize,
      height: cutOutSize,
    );

    final rrect = RRect.fromRectAndRadius(cutOutRect, const Radius.circular(28));

    final clearPaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRRect(rrect, clearPaint);
    canvas.restore();

    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.70)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawRRect(rrect, borderPaint);

    final accentPaint = Paint()
      ..color = accent.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    const corner = 26.0;
    final tl = cutOutRect.topLeft;
    final tr = cutOutRect.topRight;
    final bl = cutOutRect.bottomLeft;
    final br = cutOutRect.bottomRight;

    canvas.drawLine(tl, tl.translate(corner, 0), accentPaint);
    canvas.drawLine(tl, tl.translate(0, corner), accentPaint);

    canvas.drawLine(tr, tr.translate(-corner, 0), accentPaint);
    canvas.drawLine(tr, tr.translate(0, corner), accentPaint);

    canvas.drawLine(bl, bl.translate(corner, 0), accentPaint);
    canvas.drawLine(bl, bl.translate(0, -corner), accentPaint);

    canvas.drawLine(br, br.translate(-corner, 0), accentPaint);
    canvas.drawLine(br, br.translate(0, -corner), accentPaint);
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) => oldDelegate.accent != accent;
}
