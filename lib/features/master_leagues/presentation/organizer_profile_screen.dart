import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../../leagues/models/league.dart';
import '../domain/master_league.dart';
import '../logic/master_leagues_providers.dart';

class OrganizerProfileScreen extends ConsumerStatefulWidget {
  const OrganizerProfileScreen({
    super.key,
    required this.masterLeagueId,
  });

  final String masterLeagueId;

  @override
  ConsumerState<OrganizerProfileScreen> createState() =>
      _OrganizerProfileScreenState();
}

class _OrganizerProfileScreenState
    extends ConsumerState<OrganizerProfileScreen> {
  bool _saving = false;
  String _hydratedForId = '';

  final _bannerCtrl = TextEditingController();
  final _logoCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _badgeCtrl = TextEditingController();

  final _websiteCtrl = TextEditingController();
  final _facebookCtrl = TextEditingController();
  final _instagramCtrl = TextEditingController();
  final _xCtrl = TextEditingController();
  final _discordCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _twitchCtrl = TextEditingController();
  final _tiktokCtrl = TextEditingController();

  String get _uid => FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  @override
  void dispose() {
    _bannerCtrl.dispose();
    _logoCtrl.dispose();
    _bioCtrl.dispose();
    _badgeCtrl.dispose();
    _websiteCtrl.dispose();
    _facebookCtrl.dispose();
    _instagramCtrl.dispose();
    _xCtrl.dispose();
    _discordCtrl.dispose();
    _youtubeCtrl.dispose();
    _twitchCtrl.dispose();
    _tiktokCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final text = msg.trim();
    if (text.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Stream<MasterLeague?> _watchMasterLeague(String id) {
    return FirebaseFirestore.instance
        .collection('master_leagues')
        .doc(id.trim())
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      if (!snap.exists) return null;
      return MasterLeague.fromMap(
        snap.id,
        (snap.data() ?? <String, dynamic>{}).cast<String, dynamic>(),
      );
    }).handleError((_) => null);
  }

  Stream<List<League>> _watchCompetitions(String masterId) {
    return FirebaseFirestore.instance
        .collection('leagues')
        .where('masterLeagueId', isEqualTo: masterId.trim())
        .snapshots(includeMetadataChanges: true)
        .map((snap) {
      final list = snap.docs.map((d) {
        final map = <String, dynamic>{...d.data()};
        map['id'] = (map['id'] as String?)?.trim().isNotEmpty == true
            ? map['id']
            : d.id;
        return League.fromRemoteMap(map);
      }).toList(growable: false);

      final sorted = [...list];
      sorted.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return sorted;
    }).handleError((_) => <League>[]);
  }

  void _loadControllersFrom(MasterLeague ml) {
    if (_hydratedForId == ml.id) return;
    _hydratedForId = ml.id;

    final op = ml.organizerProfile;

    _bannerCtrl.text = op.bannerUrl;
    _logoCtrl.text = op.logoUrl;
    _bioCtrl.text = op.bio;
    _badgeCtrl.text = op.badge;

    _websiteCtrl.text = op.socialLinks['website'] ?? '';
    _facebookCtrl.text = op.socialLinks['facebook'] ?? '';
    _instagramCtrl.text = op.socialLinks['instagram'] ?? '';
    _xCtrl.text = op.socialLinks['x'] ?? op.socialLinks['twitter'] ?? '';
    _discordCtrl.text = op.socialLinks['discord'] ?? '';
    _youtubeCtrl.text = op.socialLinks['youtube'] ?? '';
    _twitchCtrl.text = op.socialLinks['twitch'] ?? '';
    _tiktokCtrl.text = op.socialLinks['tiktok'] ?? '';
  }

  OrganizerProfile _profileFromControllers() {
    final socials = <String, String>{
      'website': _websiteCtrl.text.trim(),
      'facebook': _facebookCtrl.text.trim(),
      'instagram': _instagramCtrl.text.trim(),
      'x': _xCtrl.text.trim(),
      'discord': _discordCtrl.text.trim(),
      'youtube': _youtubeCtrl.text.trim(),
      'twitch': _twitchCtrl.text.trim(),
      'tiktok': _tiktokCtrl.text.trim(),
    }..removeWhere((k, v) => v.trim().isEmpty);

    return OrganizerProfile(
      bannerUrl: _bannerCtrl.text.trim(),
      logoUrl: _logoCtrl.text.trim(),
      bio: _bioCtrl.text.trim(),
      socialLinks: socials,
      badge: _badgeCtrl.text.trim(),
    );
  }

  String? _validateProfile(OrganizerProfile p) {
    if (p.bannerUrl.length > 2000) return 'Banner URL is too long.';
    if (p.logoUrl.length > 2000) return 'Logo URL is too long.';
    if (p.bio.length > 2000) return 'Bio is too long.';
    if (p.badge.length > 80) return 'Badge is too long.';
    for (final e in p.socialLinks.entries) {
      if (e.key.length > 30) return 'Invalid social link key.';
      if (e.value.length > 2000) return 'A social link is too long.';
    }
    return null;
  }

  Future<void> _save(MasterLeague ml) async {
    if (_saving) return;

    if (!ml.isOwner(_uid)) {
      _snack(
        'Only the Master League owner can edit the organizer profile.',
        error: true,
      );
      return;
    }

    final profile = _profileFromControllers();
    final err = _validateProfile(profile);
    if (err != null) {
      _snack(err, error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);
      await repo.updateOrganizerProfile(
        masterLeagueId: ml.id,
        profile: profile,
      );
      ref.invalidate(masterLeagueByIdProvider(widget.masterLeagueId));
      ref.invalidate(myMasterLeaguesProvider);
      _snack('Organizer profile updated');
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _imageBox({
    required String url,
    required double height,
    required BorderRadius radius,
  }) {
    final cs = Theme.of(context).colorScheme;
    if (url.trim().isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: cs.onSurface.withOpacity(0.06),
          border: Border.all(color: cs.onSurface.withOpacity(0.10)),
        ),
        child: Center(
          child: Text(
            'No image',
            style: TextStyle(
              color: cs.onSurface.withOpacity(0.60),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url.trim(),
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: cs.error.withOpacity(0.06),
              border: Border.all(color: cs.error.withOpacity(0.18)),
            ),
            child: Center(
              child: Text(
                'Image failed to load',
                style: TextStyle(
                  color: cs.error,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _metricRow({
    required ThemeData theme,
    required ColorScheme cs,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialEditor() {
    return Column(
      children: [
        TextField(
          controller: _websiteCtrl,
          decoration: const InputDecoration(
            labelText: 'Website link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _facebookCtrl,
          decoration: const InputDecoration(
            labelText: 'Facebook link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _instagramCtrl,
          decoration: const InputDecoration(
            labelText: 'Instagram link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _xCtrl,
          decoration: const InputDecoration(
            labelText: 'X / Twitter link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _discordCtrl,
          decoration: const InputDecoration(
            labelText: 'Discord link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _youtubeCtrl,
          decoration: const InputDecoration(
            labelText: 'YouTube link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _twitchCtrl,
          decoration: const InputDecoration(
            labelText: 'Twitch link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tiktokCtrl,
          decoration: const InputDecoration(
            labelText: 'TikTok link (optional)',
            prefixIcon: Icon(Icons.link),
          ),
        ),
      ],
    );
  }

  Widget _pill({
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.28)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _accessDenied() {
    return const Center(
      child: EmptyState(
        title: 'No access',
        message:
            'This page is visible only to the Master League owner, admins, and moderators.',
        icon: Icons.lock_outline_rounded,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<MasterLeague?>(
      stream: _watchMasterLeague(widget.masterLeagueId),
      builder: (context, snap) {
        final ml = snap.data;

        if (snap.connectionState == ConnectionState.waiting && ml == null) {
          return const GlassScaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (ml == null) {
          return GlassScaffold(
            appBar: AppBar(
              title: const Text('Organizer Profile'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            body: const Center(
              child: EmptyState(
                title: 'Not found',
                message: 'This Master League may have been deleted.',
                icon: Icons.badge_outlined,
              ),
            ),
          );
        }

        if (!ml.canSeeOrganizerProfile(_uid)) {
          return GlassScaffold(
            appBar: AppBar(
              title: const Text('Organizer Profile'),
              backgroundColor: Colors.transparent,
              elevation: 0,
            ),
            body: _accessDenied(),
          );
        }

        _loadControllersFrom(ml);
        final isOwner = ml.isOwner(_uid);

        return GlassScaffold(
          appBar: AppBar(
            title: const Text('Organizer Profile'),
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: [
              if (isOwner)
                TextButton(
                  onPressed: _saving ? null : () => _save(ml),
                  child: Text(
                    _saving ? 'Saving...' : 'Save',
                    style: TextStyle(
                      color: _saving
                          ? cs.onSurface.withOpacity(0.55)
                          : cs.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: ListView(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
                  children: [
                    Glass(
                      borderRadius: 28,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<UserProfile?>(
                            future: UserProfileRepository().fetchByUserId(
                              ml.ownerId,
                            ),
                            builder: (context, ownerSnap) {
                              final ownerName =
                                  ownerSnap.data?.teamName.trim() ?? '';
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ml.name.trim().isEmpty
                                        ? 'Organizer'
                                        : ml.name.trim(),
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    ownerName.isNotEmpty
                                        ? 'Owner: $ownerName'
                                        : 'Owner: ${ml.ownerId}',
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurface.withOpacity(0.70),
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _pill(
                                text: ml.plan.displayName,
                                color: cs.primary,
                              ),
                              if (ml.organizerProfile.badge.trim().isNotEmpty)
                                _pill(
                                  text: ml.organizerProfile.badge.trim(),
                                  color: const Color(0xFFF59E0B),
                                ),
                              if (isOwner)
                                _pill(
                                  text: 'Owner',
                                  color: const Color(0xFF22C55E),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _imageBox(
                            url: ml.organizerProfile.bannerUrl,
                            height: 140,
                            radius: BorderRadius.circular(22),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _imageBox(
                                  url: ml.organizerProfile.logoUrl,
                                  height: 120,
                                  radius: BorderRadius.circular(22),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Glass(
                                  borderRadius: 22,
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Organizer Analytics',
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      _metricRow(
                                        theme: theme,
                                        cs: cs,
                                        label: 'Total tournaments',
                                        value:
                                            '${ml.analytics.totalTournamentsCreated}',
                                      ),
                                      _metricRow(
                                        theme: theme,
                                        cs: cs,
                                        label: 'Total participant teams',
                                        value:
                                            '${ml.analytics.totalParticipantsTeams}',
                                      ),
                                      _metricRow(
                                        theme: theme,
                                        cs: cs,
                                        label: 'Total matches',
                                        value:
                                            '${ml.analytics.totalMatches}',
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Structure ready (can be rolled up later).',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurface.withOpacity(0.60),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Glass(
                      borderRadius: 28,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'About',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            ml.organizerProfile.bio.trim().isEmpty
                                ? 'No bio yet.'
                                : ml.organizerProfile.bio.trim(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.80),
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (isOwner) ...[
                            const SizedBox(height: 14),
                            TextField(
                              controller: _bioCtrl,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                labelText: 'Organizer bio',
                                prefixIcon: Icon(Icons.subject_outlined),
                                alignLabelWithHint: true,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Glass(
                      borderRadius: 28,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Social Links',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (ml.organizerProfile.socialLinks.isEmpty)
                            Text(
                              'No social links yet.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.65),
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          else
                            ...ml.organizerProfile.socialLinks.entries.map((e) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '${e.key}: ${e.value}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.80),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              );
                            }),
                          if (isOwner) ...[
                            const SizedBox(height: 14),
                            _socialEditor(),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Glass(
                      borderRadius: 28,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Appearance',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (!isOwner)
                            Text(
                              'Only the owner can edit banner, logo, and badge.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.65),
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          else ...[
                            TextField(
                              controller: _badgeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Organizer badge (optional)',
                                prefixIcon: Icon(Icons.verified_outlined),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _bannerCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Banner image URL (optional)',
                                prefixIcon: Icon(Icons.image_outlined),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _logoCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Logo image URL (optional)',
                                prefixIcon: Icon(Icons.image_outlined),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Glass(
                      borderRadius: 28,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tournament History',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          StreamBuilder<List<League>>(
                            stream: _watchCompetitions(ml.id),
                            builder: (context, leaguesSnap) {
                              final leagues =
                                  leaguesSnap.data ?? const <League>[];
                              if (leaguesSnap.connectionState ==
                                      ConnectionState.waiting &&
                                  leagues.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              if (leagues.isEmpty) {
                                return Text(
                                  'No competitions yet.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurface.withOpacity(0.65),
                                    fontWeight: FontWeight.w700,
                                  ),
                                );
                              }

                              return Column(
                                children: leagues.take(20).map((l) {
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: InkWell(
                                      onTap: () => context.push('/leagues/${l.id}'),
                                      borderRadius: BorderRadius.circular(16),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.emoji_events_outlined,
                                            color: cs.primary,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              l.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme
                                                  .textTheme.bodyMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            l.format.displayName,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color: cs.onSurface
                                                  .withOpacity(0.65),
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(growable: false),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
