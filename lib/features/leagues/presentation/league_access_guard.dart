import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
  Object? _error;

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _checkAccess();
  }

  String _friendlyMessage(Object error) {
    if (error is SocketException) {
      return 'Your network appears to be offline. Please check your connection and try again.';
    }
    if (error is TimeoutException) {
      return 'Your internet connection seems unstable. Please try again.';
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
          return 'Your network appears to be offline. Please check your connection and try again.';
        case 'permission-denied':
          return 'You don’t have access to this league.';
        case 'unauthenticated':
          return 'Please sign in and try again.';
        default:
          return "We couldn't verify access right now. Please try again.";
      }
    }
    return "We couldn't verify access right now. Please try again.";
  }

  Future<void> _checkAccess() async {
    setState(() {
      _loading = true;
      _allowed = false;
      _error = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
      if (uid.isEmpty) {
        // Router should already redirect, but keep guard safe.
        if (mounted) context.go('/login');
        return;
      }

      final doc = await _firestore
          .collection('leagues')
          .doc(widget.leagueId)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 15));

      if (!doc.exists) {
        throw const FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
      }

      final data = doc.data() ?? <String, dynamic>{};
      final memberIdsRaw = data['memberIds'];

      final memberIds = (memberIdsRaw is List)
          ? memberIdsRaw.map((e) => (e ?? '').toString().trim()).where((s) => s.isNotEmpty).toSet()
          : <String>{};

      final allowed = memberIds.contains(uid);

      if (!mounted) return;
      setState(() {
        _allowed = allowed;
        _loading = false;
        _error = allowed ? null : const FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
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

    final message = _error == null ? 'You don’t have access to this league.' : _friendlyMessage(_error as Object);

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
