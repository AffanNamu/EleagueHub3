// lib/features/master_leagues/presentation/public_organizer_discovery_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/country/country_resolver_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/master_leagues_repository_firebase.dart';
import '../domain/master_league.dart';
import 'widgets/master_league_card.dart';

/// Discover eSportlyic organizer workspaces.
///
/// FIXED / ADDED: organizers are now also auto-loaded by the viewer's
/// resolved country ("Organizers Near You"), the same pattern already
/// used for Teams — and a dedicated search box supports finding a
/// workspace by its exact @username, in addition to browsing the
/// Featured / Verified / Recent sections.
class PublicOrganizerDiscoveryScreen extends StatefulWidget {
  const PublicOrganizerDiscoveryScreen({super.key});

  @override
  State<PublicOrganizerDiscoveryScreen> createState() =>
      _PublicOrganizerDiscoveryScreenState();
}

class _PublicOrganizerDiscoveryScreenState
    extends State<PublicOrganizerDiscoveryScreen> {
  final MasterLeaguesRepositoryFirebase _repo = MasterLeaguesRepositoryFirebase();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  bool _searching = false;
  bool _hasSearched = false;
  MasterLeague? _searchResult;
  String? _searchError;

  bool _loadingFeatured = true;
  bool _loadingVerified = true;
  bool _loadingRecent = true;
  bool _loadingNearby = true;

  List<MasterLeague> _featured = const [];
  List<MasterLeague> _verified = const [];
  List<MasterLeague> _recent = const [];
  List<MasterLeague> _nearby = const [];
  String _nearbyCountry = '';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    unawaited(_loadFeatured());
    unawaited(_loadVerified());
    unawaited(_loadRecent());
    unawaited(_loadNearby());
  }

  Future<void> _loadFeatured() async {
    try {
      final data = await _repo.discoverFeaturedOrganizers(limit: 8);
      if (!mounted) return;
      setState(() {
        _featured = data;
        _loadingFeatured = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFeatured = false);
    }
  }

  Future<void> _loadVerified() async {
    try {
      final data = await _repo.discoverVerifiedOrganizers(limit: 12);
      if (!mounted) return;
      setState(() {
        _verified = data;
        _loadingVerified = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingVerified = false);
    }
  }

  Future<void> _loadRecent() async {
    try {
      final data = await _repo.discoverRecentActiveOrganizers(limit: 12);
      if (!mounted) return;
      setState(() {
        _recent = data;
        _loadingRecent = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRecent = false);
    }
  }

  Future<void> _loadNearby() async {
    if (mounted) setState(() => _loadingNearby = true);
    try {
      final cc = await CountryResolverService.instance.resolveCountryCode();
      final data = await _repo.discoverNearbyOrganizers(countryCode: cc, limit: 12);
      if (!mounted) return;
      setState(() {
        _nearbyCountry = cc;
        _nearby = data;
        _loadingNearby = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingNearby = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _hasSearched = false;
        _searchResult = null;
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _searching = true;
      _hasSearched = true;
      _searchError = null;
    });
    try {
      final result = await _repo.fetchWorkspaceByUsername(query);
      if (!mounted) return;
      setState(() {
        _searchResult = result;
        _searching = false;
        _searchError = result == null ? 'No organizer found for that username.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = 'Something went wrong. Please try again.';
      });
    }
  }

  void _openWorkspace(MasterLeague ml) {
    context.push('/master-leagues/${ml.id}');
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Organizer Discovery'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search organizer by @username…',
                  prefixIcon: const Icon(Icons.alternate_email_rounded),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                ),
              ),
              if (_hasSearched) ...[
                const SizedBox(height: 12),
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_searchResult != null)
                  MasterLeagueCard(
                    masterLeague: _searchResult!,
                    onTap: () => _openWorkspace(_searchResult!),
                  )
                else if (_searchError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _searchError!,
                      style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: 8),
              ],

              const SizedBox(height: 16),
              _SectionHeader(
                icon: Icons.public_rounded,
                title: _nearbyCountry.isEmpty ? 'Organizers Near You' : 'Organizers in $_nearbyCountry',
              ),
              const SizedBox(height: 10),
              if (_loadingNearby)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (_nearby.isEmpty)
                _EmptyHint(text: 'No organizers found in your region yet.')
              else
                Column(
                  children: [
                    for (final ml in _nearby) ...[
                      MasterLeagueCard(masterLeague: ml, onTap: () => _openWorkspace(ml)),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),

              const SizedBox(height: 22),
              _SectionHeader(icon: Icons.star_rounded, title: 'Featured Organizers'),
              const SizedBox(height: 10),
              if (_loadingFeatured)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (_featured.isEmpty)
                _EmptyHint(text: 'No featured organizers right now.')
              else
                Column(
                  children: [
                    for (final ml in _featured) ...[
                      MasterLeagueCard(masterLeague: ml, onTap: () => _openWorkspace(ml)),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),

              const SizedBox(height: 22),
              _SectionHeader(icon: Icons.verified_rounded, title: 'Verified Organizers'),
              const SizedBox(height: 10),
              if (_loadingVerified)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (_verified.isEmpty)
                _EmptyHint(text: 'No verified organizers yet.')
              else
                Column(
                  children: [
                    for (final ml in _verified) ...[
                      MasterLeagueCard(masterLeague: ml, onTap: () => _openWorkspace(ml)),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),

              const SizedBox(height: 22),
              _SectionHeader(icon: Icons.bolt_rounded, title: 'Recently Active'),
              const SizedBox(height: 10),
              if (_loadingRecent)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (_recent.isEmpty)
                _EmptyHint(text: 'No active organizers yet.')
              else
                Column(
                  children: [
                    for (final ml in _recent) ...[
                      MasterLeagueCard(masterLeague: ml, onTap: () => _openWorkspace(ml)),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.limeAccentDark),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppTheme.primaryText(brightness)),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        text,
        style: TextStyle(color: AppTheme.secondaryText(brightness), fontWeight: FontWeight.w600),
      ),
    );
  }
}
