import 'dart:ui';

import 'package:eleaguehub3/features/leagues/logic/league_charges_payment_service.dart';
import 'package:eleaguehub3/features/leagues/logic/league_charges_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/league_flip_card.dart';
import '../data/leagues_repository_local.dart';
import '../models/enums.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import '../utils/current_user.dart';

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});

  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> with WidgetsBindingObserver {
  bool _isScanned = false;

  League? _joinedLeague;
  bool _joining = false;
  String? _error;

  late final MobileScannerController _scannerController;

  bool _torchOn = false;
  CameraFacing _facing = CameraFacing.back;

  String _currentUserId = '';
  bool _chargesPaid = false;

  LeagueJoinMode? _joinedMode;

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
      setState(() {
        _requestingPermission = false;
        _error = 'Permission error: $e';
      });
    }
  }

  Future<void> _startScannerSafely() async {
    if (_scannerStarted) return;
    try {
      await _scannerController.start();
      _scannerStarted = true;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to start camera: $e';
      });
      _scannerStarted = false;
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
                        const Text(
                          'Join league as…',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Join code: ${joinCode.toUpperCase()}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        _JoinModeTile(
                          title: 'Participant',
                          subtitle: 'You will be counted as a participant in this league.',
                          icon: Icons.sports_esports,
                          accent: Colors.cyanAccent,
                          onTap: () => Navigator.of(ctx).pop(LeagueJoinMode.participant),
                        ),
                        const SizedBox(height: 10),
                        _JoinModeTile(
                          title: 'Viewer only',
                          subtitle: 'You can browse the league, but you won’t be counted as a participant.',
                          icon: Icons.visibility,
                          accent: Colors.white70,
                          onTap: () => Navigator.of(ctx).pop(LeagueJoinMode.viewer),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(null),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
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

  Future<void> _handleScan(String payload) async {
    if (_joining) return;

    final parsed = _parseJoinPayload(payload);
    if (parsed == null) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Invalid QR / Join code.';
        _isScanned = false;
      });
      await _startScannerSafely();
      return;
    }

    final joinCode = parsed.code;

    final mode = await _promptJoinMode(context, joinCode: joinCode);
    if (mode == null) {
      // User cancelled
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
    });

    final prefs = ref.read(prefsServiceProvider);
    final repo = LocalLeaguesRepository(prefs);

    // Firebase Auth uid (immutable userId). No extra UI prompts.
    final currentUserId = await CurrentUser.getUserId();

    try {
      final league = await repo.joinLeagueLocallyByCode(
        joinCode: joinCode,
        userId: currentUserId,
        mode: mode,
        placeholderBuilder: (generatedLeagueId) {
          final now = DateTime.now().millisecondsSinceEpoch;
          return League(
            id: generatedLeagueId,
            name: 'Joined League',
            format: LeagueFormat.classic,
            privacy: LeaguePrivacy.private,
            region: 'Global',
            maxTeams: 20,
            season: '2026',
            organizerUserId: '',
            code: joinCode,
            qrPayloadOverride: '',
            settings: LeagueSettings.defaultsFor(LeagueFormat.classic).copyWith(
              lastPulledAtMs: now,
            ),
            updatedAtMs: now,
            version: 1,
          );
        },
      );

      if (!mounted) return;

      final store = LeagueChargesStore(prefs);
      final paid = store.hasPaidCharges(userId: currentUserId, leagueId: league.id);

      setState(() {
        _joinedLeague = league;
        _joining = false;
        _currentUserId = currentUserId;
        _chargesPaid = paid;
        _joinedMode = mode;
      });

      await _maybePromptChargesAfterJoin(
        context,
        joinedLeague: league,
        userId: currentUserId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Join failed: $e';
        _isScanned = false;
      });
      await _startScannerSafely();
    }
  }

  bool _requiresCharges(League league) {
    return league.format == LeagueFormat.uclGroup || league.format == LeagueFormat.uclSwiss;
  }

  bool _isCreator(League league, String userId) {
    return league.organizerUserId == userId;
  }

  Future<void> _maybePromptChargesAfterJoin(
    BuildContext context, {
    required League joinedLeague,
    required String userId,
  }) async {
    if (!_requiresCharges(joinedLeague)) return;
    if (_isCreator(joinedLeague, userId)) return;

    final prefs = ref.read(prefsServiceProvider);
    final store = LeagueChargesStore(prefs);

    final alreadyPaid = store.hasPaidCharges(userId: userId, leagueId: joinedLeague.id);
    if (alreadyPaid) {
      if (!mounted) return;
      setState(() => _chargesPaid = true);
      return;
    }

    final shouldPay = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0A1D37),
          title: const Text(
            'Unlock Fixtures & Standings',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'This league requires charges to view Fixtures and Standings.\n\nLeague: ${joinedLeague.name}\n\nPay now to unlock, or choose Later and pay when you open Fixtures/Standings.',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Later', style: TextStyle(color: Colors.white70)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Pay now'),
            ),
          ],
        );
      },
    );

    if (shouldPay != true) return;

    await _unlockNow(context, league: joinedLeague, userId: userId);
  }

  Future<void> _unlockNow(
    BuildContext context, {
    required League league,
    required String userId,
  }) async {
    final prefs = ref.read(prefsServiceProvider);
    final store = LeagueChargesStore(prefs);

    final alreadyPaid = store.hasPaidCharges(userId: userId, leagueId: league.id);
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

      final result = await paymentService.payLeagueCharges(
        context: context,
        userId: userId,
        leagueId: league.id,
        leagueName: league.name,
      );

      if (!mounted) return;

      if (!result.success) {
        setState(() {
          _joining = false;
          _error = result.errorMessage ?? 'Payment failed';
        });
        return;
      }

      final receipt = LeagueChargesReceipt(
        leagueId: league.id,
        userId: userId,
        receiptId: result.receiptId ?? '',
        provider: result.provider,
        paidAtMs: result.paidAtMs,
      );

      await store.storeReceipt(receipt);

      if (!mounted) return;
      setState(() {
        _joining = false;
        _chargesPaid = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unlocked successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Payment failed: $e';
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
                          const Text(
                            'Enter Join Code',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Paste the Join ID (letters/numbers) from the organizer.',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: controller,
                            autofocus: true,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            textCapitalization: TextCapitalization.characters,
                            decoration: InputDecoration(
                              hintText: 'e.g. ABC123',
                              hintStyle: const TextStyle(color: Colors.white38),
                              prefixIcon: const Icon(Icons.key, color: Colors.white70),
                              suffixIcon: IconButton(
                                tooltip: 'Paste',
                                icon: const Icon(Icons.content_paste, color: Colors.cyanAccent),
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
                                  child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                                  icon: const Icon(Icons.login),
                                  label: const Text('Continue'),
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

  @override
  Widget build(BuildContext context) {
    if (_joinedLeague != null) {
      final league = _joinedLeague!;
      final screenWidth = MediaQuery.of(context).size.width;
      final isWide = screenWidth > 600;

      final requiresCharges = _requiresCharges(league);
      final isCreator = _currentUserId.isNotEmpty && _isCreator(league, _currentUserId);
      final showUnlock = requiresCharges && !isCreator && !_chargesPaid;

      final mode = _joinedMode;
      final joinedLine = (mode == LeagueJoinMode.viewer)
          ? 'You joined as Viewer (not counted as a participant).'
          : 'You joined as Participant.';

      return GlassScaffold(
        appBar: AppBar(
          title: const Text('League Joined'),
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
                      distribution: '${league.format.displayName} • ${league.season}',
                      subtitle: '0 / ${league.maxTeams} teams',
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
                            '$joinedLine\n\n${showUnlock ? 'This league requires charges to view fixtures & standings.' : 'You can open the league now.'}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (showUnlock) ...[
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _joining
                                    ? null
                                    : () => _unlockNow(
                                          context,
                                          league: league,
                                          userId: _currentUserId,
                                        ),
                                icon: _joining
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.lock_open),
                                label: const Text('UNLOCK NOW'),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => context.go('/leagues'),
                                  child: const Text('DONE'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => context.push('/leagues/${league.id}'),
                                  child: const Text('OPEN'),
                                ),
                              ),
                            ],
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
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
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Glass(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.camera_alt_outlined, color: Colors.white70, size: 34),
                          const SizedBox(height: 10),
                          const Text(
                            'Camera not available',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            error.toString(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () async {
                              setState(() {
                                _error = null;
                                _isScanned = false;
                              });
                              await _ensureCameraPermission(startScannerIfGranted: true);
                            },
                            child: const Text('Retry'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _joining ? null : _showManualEntrySheet,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.white.withOpacity(0.18)),
                              foregroundColor: Colors.cyanAccent,
                            ),
                            child: const Text('Enter code instead'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Overlay with cut-out
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ScannerOverlayPainter(),
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 26),
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _joining ? null : _showManualEntrySheet,
                    child: const Text(
                      'ENTER CODE',
                      style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_cameraPermissionGranted) ...[
                    IconButton(
                      tooltip: _torchOn ? 'Torch off' : 'Torch on',
                      icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
                      onPressed: () async {
                        await _scannerController.toggleTorch();
                        setState(() => _torchOn = !_torchOn);
                      },
                    ),
                    IconButton(
                      tooltip: 'Switch camera',
                      icon: const Icon(Icons.cameraswitch, color: Colors.white),
                      onPressed: () async {
                        final newFacing = _facing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
                        await _scannerController.switchCamera();
                        setState(() => _facing = newFacing);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 120,
            child: Center(
              child: _joining
                  ? const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        color: Colors.cyanAccent,
                        strokeWidth: 3,
                      ),
                    )
                  : Text(
                      _cameraPermissionGranted ? 'Center the QR code within the frame' : 'Camera permission is required',
                      style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),

          if (!_cameraPermissionGranted && _permissionChecked)
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Glass(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Allow Camera Access',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'To scan league QR codes, enable camera permission.\n\nOr tap ENTER CODE to join manually.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.70), height: 1.35),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _requestingPermission ? null : () => openAppSettings(),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.white.withOpacity(0.18)),
                                  foregroundColor: Colors.white70,
                                ),
                                child: const Text('Open settings'),
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
                                    : const Text('Grant permission'),
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

          if (_error != null && _cameraPermissionGranted)
            Positioned(
              bottom: 70,
              left: 16,
              right: 16,
              child: Center(
                child: Glass(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

          if (_cameraPermissionGranted)
            Positioned(
              bottom: 18,
              left: 16,
              right: 16,
              child: Center(
                child: TextButton(
                  onPressed: _joining
                      ? null
                      : () async {
                          setState(() {
                            _error = null;
                            _isScanned = false;
                            _joining = false;
                          });
                          await _ensureCameraPermission(startScannerIfGranted: true);
                        },
                  child: const Text(
                    'SCAN AGAIN',
                    style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w900),
                  ),
                ),
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
    return Glass(
      borderRadius: 20,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: accent.withOpacity(0.18),
          child: Icon(icon, color: accent),
        ),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.25),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
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
      ..color = Colors.cyanAccent.withOpacity(0.85)
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
