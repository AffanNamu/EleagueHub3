import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/widgets/glass.dart';

class LeagueAccessGuard extends StatefulWidget {
  final String leagueId;
  final Widget child;

  const LeagueAccessGuard({
    super.key,
    required this.leagueId,
    required this.child,
  });

  @override
  State<LeagueAccessGuard> createState() => _LeagueAccessGuardState();
}

class _LeagueAccessGuardState extends State<LeagueAccessGuard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _loading = true;
  bool _allowed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _checkAccess();
  }

  Future<void> _checkAccess() async {
    setState(() {
      _loading = true;
      _allowed = false;
      _errorMessage = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (uid.isEmpty) {
        if (mounted) context.go('/login');
        return;
      }

      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final doc = await _firestore
          .collection('leagues')
          .doc(widget.leagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (!doc.exists) {
        if (!mounted) return;
        setState(() {
          _allowed = false;
          _loading = false;
          _errorMessage = 'You don\'t have access to this league.';
        });
        return;
      }

      final data = doc.data() ?? <String, dynamic>{};

      final memberIdsRaw = data['memberIds'];
      final memberIds = (memberIdsRaw is List)
          ? memberIdsRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toSet()
          : <String>{};

      final organizerUid = (data['organizerUid'] ?? '').toString().trim();
      final ownerUid = (data['ownerUid'] ?? '').toString().trim();

      final allowed = memberIds.contains(uid) || organizerUid == uid || ownerUid == uid;

      if (!mounted) return;
      setState(() {
        _allowed = allowed;
        _loading = false;
        _errorMessage = allowed ? null : 'You don\'t have access to this league.';
      });
    } catch (e) {
      if (!mounted) return;

      var msg = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));

      if (msg == 'You don\'t have permission to do that right now.') {
        msg = 'You don\'t have access to this league.';
      }

      setState(() {
        _errorMessage = msg;
        _loading = false;
        _allowed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_allowed) return widget.child;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: cs.primary),
            const SizedBox(height: 16),
            Text(
              'Checking access...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final message = (_errorMessage ?? 'You don\'t have access to this league.').trim();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Glass(
            borderRadius: 26,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lock icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        cs.primary.withOpacity(0.25),
                        cs.primary.withOpacity(0.08),
                      ],
                    ),
                  ),
                  child: Icon(Icons.lock_outline_rounded, color: cs.primary, size: 30),
                ),
                const SizedBox(height: 18),

                Text(
                  'Access Restricted',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),

                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => context.pop(),
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            height: 46,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withOpacity(0.15)),
                              color: Colors.white.withOpacity(0.05),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.arrow_back_ios_new_rounded,
                                      size: 16, color: Colors.white.withOpacity(0.7)),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Back',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.7),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _checkAccess,
                          borderRadius: BorderRadius.circular(14),
                          child: Ink(
                            height: 46,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              gradient: LinearGradient(
                                colors: [
                                  cs.primary,
                                  cs.primary.withOpacity(0.75),
                                ],
                              ),
                              border: Border.all(color: cs.primary.withOpacity(0.40)),
                            ),
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.refresh_rounded, size: 18, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'Retry',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
