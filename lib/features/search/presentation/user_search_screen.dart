//lib/features/search/user_search_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/country/country_resolver_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../profile/models/game_id.dart';
import '../data/user_search_repository.dart';
import '../models/user_search_entry.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final UserSearchRepository _repo = UserSearchRepository();
  final TextEditingController _controller = TextEditingController();

  Timer? _debounce;
  List<UserSearchEntry> _results = const [];
  bool _loading = false;
  bool _searched = false;

  // "Teams Near You" — auto-loaded, independent of the manual search box.
  bool _nearbyLoading = true;
  List<UserSearchEntry> _nearby = const [];
  String _nearbyCountry = '';

  @override
  void initState() {
    super.initState();
    _loadNearby();
  }

  Future<void> _loadNearby() async {
    if (mounted) setState(() => _nearbyLoading = true);
    try {
      final cc = await CountryResolverService.instance.resolveCountryCode();
      final entries = await _repo.fetchNearby(countryCode: cc);
      if (!mounted) return;
      setState(() {
        _nearbyCountry = cc;
        _nearby = entries;
        _nearbyLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _nearbyLoading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _runSearch(value));
  }

  Future<void> _runSearch(String query) async {
    setState(() => _loading = true);
    final results = await _repo.search(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final bool showingManualSearch = _searched;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Search Teams'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'Search by team name or ID…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        ),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: showingManualSearch
                  ? _buildSearchResults(brightness)
                  : _buildNearbySection(brightness),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(Brightness brightness) {
    if (_results.isEmpty) {
      return Center(
        child: Text(
          'No teams found.',
          style: TextStyle(
            color: AppTheme.secondaryText(brightness),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) => _TeamTile(entry: _results[i]),
    );
  }

  Widget _buildNearbySection(Brightness brightness) {
    return RefreshIndicator(
      onRefresh: _loadNearby,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Row(
            children: [
              Icon(Icons.public_rounded, size: 16, color: AppTheme.limeAccentDark),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _nearbyCountry.isEmpty ? 'Teams Near You' : 'Teams in $_nearbyCountry',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppTheme.primaryText(brightness),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Automatically shown based on your region. Use the search box above to find a specific team.',
            style: TextStyle(
              color: AppTheme.secondaryText(brightness),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 14),
          if (_nearbyLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_nearby.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No nearby teams found yet. Try searching by name or Team ID instead.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else
            Column(
              children: [
                for (final entry in _nearby) ...[
                  _TeamTile(entry: entry),
                  const SizedBox(height: 8),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({required this.entry});
  final UserSearchEntry entry;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Glass(
      borderRadius: 16,
      padding: EdgeInsets.zero,
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.iconCircleBackground(brightness),
          backgroundImage: entry.avatarUrl.isNotEmpty ? NetworkImage(entry.avatarUrl) : null,
          child: entry.avatarUrl.isEmpty ? const Icon(Icons.person_rounded) : null,
        ),
        title: Text(
          entry.displayName,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppTheme.primaryText(brightness),
          ),
        ),
        subtitle: Text(
          entry.game.isEmpty ? entry.shareId : '${GameId.label(entry.game)} · ${entry.shareId}',
          style: TextStyle(color: AppTheme.secondaryText(brightness)),
        ),
        onTap: () => context.push('/profile/${entry.userId}'),
      ),
    );
  }
}
