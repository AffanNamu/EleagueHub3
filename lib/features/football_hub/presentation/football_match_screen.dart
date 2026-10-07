// lib/features/football_hub/presentation/football_match_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/football_api_service.dart';
import '../models/football_fixture.dart';
import '../models/football_match_event.dart';

/// Match Details: the written Football Hub plan's section D -- teams,
/// logos, competition, kickoff, score, status, and the events timeline
/// (goals/cards/subs) where the provider supports them.
///
/// Prefer passing the already-fetched [fixture] (from the Matches list or
/// a team's next/last fixtures) -- every avoided request matters on a
/// 100-requests/day provider quota. [fixtureId] alone is the deep-link
/// path (`/football/match/{id}`, e.g. a future notification tap landing
/// cold), where nothing is in memory yet and this screen fetches the
/// fixture itself before rendering.
class FootballMatchScreen extends StatefulWidget {
  FootballMatchScreen({super.key, this.fixture, int? fixtureId})
      : assert(fixture != null || fixtureId != null, 'Provide fixture or fixtureId'),
        fixtureId = fixtureId ?? fixture!.id;

  final FootballFixture? fixture;
  final int fixtureId;

  @override
  State<FootballMatchScreen> createState() => _FootballMatchScreenState();
}

class _FootballMatchScreenState extends State<FootballMatchScreen> {
  final _service = FootballApiService();
  late Future<FootballFixture?> _fixtureFuture;
  Future<List<FootballMatchEvent>>? _eventsFuture;
  DateTime? _lastFetchedAt;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _fixtureFuture = widget.fixture != null
        ? Future.value(widget.fixture)
        : _service.getFixtureById(widget.fixtureId);
    _eventsFuture = _load();
    // Re-render every 30s so the "updated Xs ago" label stays live without
    // re-fetching anything -- purely a local clock tick.
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<List<FootballMatchEvent>> _load() async {
    final events = await _service.getFixtureEvents(fixtureId: widget.fixtureId);
    _lastFetchedAt = DateTime.now();
    return events;
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  String _agoLabel() {
    final at = _lastFetchedAt;
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 60) return 'Updated ${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes} min ago';
    return 'Updated ${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FootballFixture?>(
      future: _fixtureFuture,
      builder: (context, fixtureSnap) {
        if (fixtureSnap.connectionState != ConnectionState.done) {
          return const GlassScaffold(body: Center(child: CircularProgressIndicator()));
        }
        final f = fixtureSnap.data;
        if (fixtureSnap.hasError || f == null) {
          final message = fixtureSnap.hasError
              ? UserFriendlyError.toMessage(fixtureSnap.error!)
              : 'Football data temporarily unavailable. Please try again.';
          return GlassScaffold(
            appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(message, textAlign: TextAlign.center),
                ),
              ),
            ),
          );
        }
        return _MatchDetailsBody(fixture: f, eventsFuture: _eventsFuture!, agoLabel: _agoLabel);
      },
    );
  }
}

class _MatchDetailsBody extends StatelessWidget {
  const _MatchDetailsBody({required this.fixture, required this.eventsFuture, required this.agoLabel});

  final FootballFixture fixture;
  final Future<List<FootballMatchEvent>> eventsFuture;
  final String Function() agoLabel;

  @override
  Widget build(BuildContext context) {
    final f = fixture;
    final brightness = Theme.of(context).brightness;

    String statusLabel;
    if (f.isLive) {
      statusLabel = f.elapsedMinutes != null ? "LIVE · ${f.elapsedMinutes}'" : 'LIVE';
    } else if (f.isFinished) {
      statusLabel = 'Full time';
    } else {
      statusLabel = DateFormat('EEE d MMM, HH:mm').format(f.kickoff);
    }

    return GlassScaffold(
      appBar: AppBar(
        title: Text(f.leagueName),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Glass(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _TeamHeader(name: f.homeTeamName, logoUrl: f.homeTeamLogoUrl)),
                      SizedBox(
                        width: 90,
                        child: Column(
                          children: [
                            Text(
                              (f.isLive || f.isFinished) ? '${f.homeGoals ?? 0} - ${f.awayGoals ?? 0}' : 'vs',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppTheme.primaryText(brightness),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              statusLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: f.isLive ? const Color(0xFFEF4444) : AppTheme.secondaryText(brightness),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: _TeamHeader(name: f.awayTeamName, logoUrl: f.awayTeamLogoUrl)),
                    ],
                  ),
                  if (f.round.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      f.round,
                      style: TextStyle(fontSize: 12, color: AppTheme.secondaryText(brightness)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Match events',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppTheme.secondaryText(brightness)),
                ),
                FutureBuilder<List<FootballMatchEvent>>(
                  future: eventsFuture,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const SizedBox.shrink();
                    }
                    final label = agoLabel();
                    if (label.isEmpty) return const SizedBox.shrink();
                    return Text(
                      label,
                      style: TextStyle(fontSize: 11, color: AppTheme.secondaryText(brightness)),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<FootballMatchEvent>>(
              future: eventsFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      UserFriendlyError.toMessage(snap.error!),
                      style: TextStyle(color: AppTheme.secondaryText(brightness)),
                    ),
                  );
                }
                final events = snap.data ?? const [];
                if (events.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      f.isUpcoming ? 'Events will appear once the match kicks off.' : 'No events reported for this match.',
                      style: TextStyle(color: AppTheme.secondaryText(brightness)),
                    ),
                  );
                }
                return Column(
                  children: events.map((e) => _EventRow(event: e, brightness: brightness)).toList(growable: false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamHeader extends StatelessWidget {
  const _TeamHeader({required this.name, required this.logoUrl});
  final String name;
  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Column(
      children: [
        if (logoUrl.isNotEmpty)
          Image.network(logoUrl, width: 40, height: 40, errorBuilder: (_, __, ___) => const SizedBox(width: 40, height: 40))
        else
          Icon(Icons.shield_outlined, size: 40, color: AppTheme.secondaryText(brightness)),
        const SizedBox(height: 8),
        Text(
          name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppTheme.primaryText(brightness)),
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.brightness});
  final FootballMatchEvent event;
  final Brightness brightness;

  IconData get _icon {
    if (event.isGoal) return Icons.sports_soccer;
    if (event.isCard) return Icons.square_rounded;
    if (event.isSubstitution) return Icons.swap_horiz;
    return Icons.info_outline;
  }

  Color get _iconColor {
    if (event.isGoal) return const Color(0xFF22C55E);
    if (event.isRedCard) return const Color(0xFFEF4444);
    if (event.isCard) return const Color(0xFFF59E0B);
    return AppTheme.secondaryText(brightness);
  }

  @override
  Widget build(BuildContext context) {
    final minuteLabel = event.extraMinute != null ? "${event.minute}+${event.extraMinute}'" : "${event.minute}'";

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Text(
              minuteLabel,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppTheme.secondaryText(brightness)),
            ),
          ),
          Icon(_icon, size: 18, color: _iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.playerName.isNotEmpty ? event.playerName : event.detail,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.primaryText(brightness)),
                ),
                Text(
                  [
                    event.detail,
                    if (event.assistName != null) 'Assist: ${event.assistName}',
                    event.teamName,
                  ].join(' · '),
                  style: TextStyle(fontSize: 11, color: AppTheme.secondaryText(brightness)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
