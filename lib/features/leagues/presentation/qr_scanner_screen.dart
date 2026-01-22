import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> {
  bool _isScanned = false;

  League? _joinedLeague;
  bool _joining = false;
  String? _error;

  Future<void> _handleScan(String payload) async {
    if (_joining) return;
    setState(() {
      _joining = true;
      _error = null;
    });

    final prefs = ref.read(prefsServiceProvider);
    final repo = LocalLeaguesRepository(prefs);

    // IMPORTANT: use FirebaseAuth uid (via CurrentUser), not 'admin_user'
    final currentUserId = await CurrentUser.getOrCreateUserId();

    final parsed = _parseJoinPayload(payload);
    if (parsed == null) {
      setState(() {
        _joining = false;
        _error = 'Invalid QR / Join code.';
        _isScanned = false;
      });
      return;
    }

    final joinCode = parsed.code;

    try {
      final league = await repo.joinLeagueLocallyByCode(
        joinCode: joinCode,
        userId: currentUserId,
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
      setState(() {
        _joinedLeague = league;
        _joining = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _error = 'Join failed: $e';
        _isScanned = false;
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;

    final barcode = capture.barcodes.first.rawValue;
    if (barcode == null) return;

    _isScanned = true;
    _handleScan(barcode);
  }

  @override
  Widget build(BuildContext context) {
    if (_joinedLeague != null) {
      final league = _joinedLeague!;
      final screenWidth = MediaQuery.of(context).size.width;
      final isWide = screenWidth > 600;

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
                            'You joined this league successfully.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.75),
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
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
          MobileScanner(
            onDetect: _onDetect,
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withOpacity(0.3),
              ),
            ),
          ),
          Center(
            child: Container(
              height: 260,
              width: 260,
              decoration: BoxDecoration(
                color: Colors.black,
                backgroundBlendMode: BlendMode.dstOut,
                borderRadius: BorderRadius.circular(40),
              ),
            ),
          ),
          Center(
            child: Container(
              height: 260,
              width: 260,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white70, width: 2),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Stack(
                children: [
                  _buildCorner(Alignment.topLeft),
                  _buildCorner(Alignment.topRight),
                  _buildCorner(Alignment.bottomLeft),
                  _buildCorner(Alignment.bottomRight),
                ],
              ),
            ),
          ),
          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => context.pop(),
            ),
          ),
          Positioned(
            bottom: 120,
            left: 0,
            right: 0,
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
                  : const Text(
                      'Center the QR code within the frame',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
            ),
          ),
          if (_error != null)
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

  Widget _buildCorner(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        height: 20,
        width: 20,
        decoration: BoxDecoration(
          color: Colors.blueAccent,
          borderRadius: BorderRadius.only(
            topLeft: alignment == Alignment.topLeft ? const Radius.circular(10) : Radius.zero,
            topRight: alignment == Alignment.topRight ? const Radius.circular(10) : Radius.zero,
            bottomLeft: alignment == Alignment.bottomLeft ? const Radius.circular(10) : Radius.zero,
            bottomRight: alignment == Alignment.bottomRight ? const Radius.circular(10) : Radius.zero,
          ),
        ),
      ),
    );
  }
}

class _JoinParse {
  final String code;
  const _JoinParse({required this.code});
}
