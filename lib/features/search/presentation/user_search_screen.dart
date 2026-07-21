import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
                autofocus: true,
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
              child: !_searched
                  ? Center(
                      child: Text(
                        'Find teams by name or Team ID.',
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            'No teams found.',
                            style: TextStyle(
                              color: AppTheme.secondaryText(brightness),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final entry = _results[i];
                            return Glass(
                              borderRadius: 16,
                              padding: EdgeInsets.zero,
                              fill: AppTheme.cardColor(brightness),
                              borderColor: AppTheme.cardBorder(brightness),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppTheme.iconCircleBackground(brightness),
                                  backgroundImage: entry.avatarUrl.isNotEmpty
                                      ? NetworkImage(entry.avatarUrl)
                                      : null,
                                  child: entry.avatarUrl.isEmpty
                                      ? const Icon(Icons.person_rounded)
                                      : null,
                                ),
                                title: Text(
                                  entry.displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primaryText(brightness),
                                  ),
                                ),
                                subtitle: Text(
                                  entry.game.isEmpty
                                      ? entry.shareId
                                      : '${GameId.label(entry.game)} · ${entry.shareId}',
                                  style: TextStyle(color: AppTheme.secondaryText(brightness)),
                                ),
                                onTap: () => context.push('/profile/${entry.userId}'),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
