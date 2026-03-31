import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/leagues_repository_local.dart';
import '../models/league.dart';
import '../models/membership.dart';

class LeagueRoleGuard extends StatefulWidget {
  const LeagueRoleGuard({
    super.key,
    required this.leagueId,
    required this.child,
    this.allowOrganizer = true,
    this.allowAdmin = true,
    this.title = 'Restricted Access',
    this.message = 'You do not have permission to open this page.',
  });

  final String leagueId;
  final Widget child;
  final bool allowOrganizer;
  final bool allowAdmin;
  final String title;
  final String message;

  @override
  State<LeagueRoleGuard> createState() => _LeagueRoleGuardState();
}

class _LeagueRoleGuardState extends State<LeagueRoleGuard> {
  late final Future<LocalLeaguesRepository> _repoFuture;

  Future<LocalLeaguesRepository> _buildRepo() async {
    final prefs = await PrefsService.instance;
    return LocalLeaguesRepository(prefs);
  }

  Future<bool> _checkAllowed() async {
    final uid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (uid.isEmpty) return false;

    final repo = await _repoFuture;

    final league = await repo
        .getLeagueById(widget.leagueId)
        .timeout(const Duration(seconds: 12));

    if (league == null) return false;

    final membership = await repo
        .getMembership(
          leagueId: widget.leagueId,
          userId: uid,
        )
        .timeout(const Duration(seconds: 12));

    final ownerByLeague = league.organizerUid.trim().isNotEmpty &&
        league.organizerUid.trim() == uid;

    if (widget.allowOrganizer) {
      final ownerByMembership = membership?.role == LeagueRole.organizer;
      if (ownerByLeague || ownerByMembership) return true;
    }

    if (widget.allowAdmin) {
      if (_isAdminLikeMembership(membership)) return true;
    }

    return false;
  }

  bool _isAdminLikeMembership(Membership? membership) {
    if (membership == null) return false;
    final role = membership.role;

    if (role == LeagueRole.organizer) return true;

    final roleName = role.name.toLowerCase();
    if (roleName == 'admin') return true;
    if (roleName == 'moderator') return true;

    return false;
  }

  @override
  void initState() {
    super.initState();
    _repoFuture = _buildRepo();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return FutureBuilder<bool>(
      future: _checkAllowed(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return GlassScaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Glass(
                    borderRadius: 26,
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Checking permissions…',
                            style: TextStyle(
                              color: cs.onSurface.withOpacity(0.72),
                              fontWeight: FontWeight.w900,
                            ),
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

        if (snap.data == true) {
          return widget.child;
        }

        return GlassScaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Glass(
                  borderRadius: 26,
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              cs.error.withOpacity(0.22),
                              cs.error.withOpacity(0.08),
                            ],
                          ),
                        ),
                        child: Icon(
                          Icons.admin_panel_settings_outlined,
                          color: cs.error,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        widget.title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.message,
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.68),
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/');
                            }
                          },
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text(
                            'Go Back',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
