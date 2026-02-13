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
        // Protected resources require auth; router should also guard, but keep this safe.
        if (mounted) context.go('/login');
        return;
      }

      // Online-only: fail fast when offline with a friendly message.
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 4));

      final doc = await _firestore
          .collection('leagues')
          .doc(widget.leagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (!doc.exists) {
        // Do not reveal existence; treat as restricted.
        if (!mounted) return;
        setState(() {
          _allowed = false;
          _loading = false;
          _errorMessage = 'You don’t have access to this league.';
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

      // REQUIRED: allow if memberIds contains uid OR organizerUid == uid OR ownerUid == uid.
      // Handle missing fields gracefully.
      final allowed = memberIds.contains(uid) || organizerUid == uid || ownerUid == uid;

      if (!mounted) return;
      setState(() {
        _allowed = allowed;
        _loading = false;
        _errorMessage = allowed ? null : 'You don’t have access to this league.';
      });
    } catch (e) {
      if (!mounted) return;

      // Never show raw Firebase/technical errors.
      var msg = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));

      // This guard is league-specific; keep the UX clear.
      if (msg == 'You don’t have permission to do that right now.') {
        msg = 'You don’t have access to this league.';
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
        child: CircularProgressIndicator(color: cs.primary),
      );
    }

    final message = (_errorMessage ?? 'You don’t have access to this league.').trim();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Glass(
            borderRadius: 24,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, color: cs.primary, size: 44),
                  const SizedBox(height: 10),
                  Text(
                    'Access restricted',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withOpacity(0.70),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => context.pop(),
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _checkAccess,
                          child: const Text('Retry'),
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
    );
  }
}
