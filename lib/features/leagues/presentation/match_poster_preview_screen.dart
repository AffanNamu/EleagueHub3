// lib/features/leagues/presentation/match_poster_preview_screen.dart

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../models/fixture_match.dart';
import '../models/match_poster_data.dart';
import '../models/team.dart';
import '../services/match_poster_export_service.dart';
import '../widgets/match_poster_widget.dart';

class MatchPosterPreviewScreen extends StatefulWidget {
  const MatchPosterPreviewScreen({
    super.key,
    required this.leagueId,
    required this.match,
    required this.teamsById,
  });

  final String leagueId;
  final FixtureMatch match;
  final Map<String, Team> teamsById;

  @override
  State<MatchPosterPreviewScreen> createState() =>
      _MatchPosterPreviewScreenState();
}

class _MatchPosterPreviewScreenState extends State<MatchPosterPreviewScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  final MatchPosterExportService _exportService = MatchPosterExportService();

  final TextEditingController _dateTimeCtrl = TextEditingController();
  final TextEditingController _venueCtrl = TextEditingController();

  MatchPosterFormat _format = MatchPosterFormat.portrait;

  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  MatchPosterData? _baseData;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _dateTimeCtrl.dispose();
    _venueCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _fetchLeagueFields(String leagueId) async {
    final snap = await FirebaseFirestore.instance
        .collection('leagues')
        .doc(leagueId)
        .get()
        .timeout(const Duration(seconds: 12));
    return snap.data();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final data = await MatchPosterDataBuilder.fromMatch(
        leagueId: widget.leagueId,
        match: widget.match,
        teamsById: widget.teamsById,
        fetchLeagueFields: _fetchLeagueFields,
      );

      if (!mounted) return;

      // Precache remote images before the first paint so the very first
      // preview frame (and any immediate export) already has real avatars
      // rather than fallback icons.
      await _exportService.precacheImages(context, data.remoteImageUrls);

      if (!mounted) return;
      setState(() {
        _baseData = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load match details. Please try again.';
        _loading = false;
      });
    }
  }

  MatchPosterData? get _renderData {
    final base = _baseData;
    if (base == null) return null;
    return base.copyWith(
      dateTimeLabel: _dateTimeCtrl.text.trim().isEmpty
          ? null
          : _dateTimeCtrl.text.trim(),
      venueLabel:
          _venueCtrl.text.trim().isEmpty ? null : _venueCtrl.text.trim(),
    );
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? cs.error : null,
        content: Text(msg),
      ),
    );
  }

  Future<File?> _export() async {
    // Re-precache in case the organizer changed nothing but the very first
    // load raced with image resolution — cheap no-op if already cached.
    final data = _renderData;
    if (data == null) return null;
    await _exportService.precacheImages(context, data.remoteImageUrls);
    if (!mounted) return null;

    // Let the widget settle a frame after any precache/state change.
    await Future.delayed(const Duration(milliseconds: 80));

    final bytes = await _exportService.capturePng(
      repaintBoundaryKey: _repaintKey,
      targetWidth: _format.exportWidth,
      targetHeight: _format.exportHeight,
    );

    return _exportService.saveToTempFile(bytes);
  }

  Future<void> _onShare() async {
    if (_busy) return;
    setState(() => _busy = true);
    File? file;
    try {
      file = await _export();
      if (file == null) return;
      await _exportService.shareFile(
        file,
        text: 'Match poster from eSportlyic',
      );
    } catch (e) {
      _snack(
        e is MatchPosterExportException ? e.message : 'Could not export the poster.',
        error: true,
      );
    } finally {
      if (file != null) await _exportService.deleteQuietly(file);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Match Poster'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_loadError != null)
                ? _ErrorState(message: _loadError!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: AspectRatio(
                            aspectRatio: _format.aspectRatio,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(22),
                              child: RepaintBoundary(
                                key: _repaintKey,
                                child: MatchPosterWidget(data: _renderData!),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Template',
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: const [
                          _StaticChoiceChip(label: 'Classic', selected: true),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Format',
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: MatchPosterFormat.values.map((f) {
                          final selected = f == _format;
                          return ChoiceChip(
                            label: Text(f.label),
                            selected: selected,
                            onSelected: (_) => setState(() => _format = f),
                          );
                        }).toList(growable: false),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Details (optional)',
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Not tracked elsewhere in the app yet — add them here '
                        'just for this poster if you\'d like.',
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Glass(
                        borderRadius: 18,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            TextField(
                              controller: _dateTimeCtrl,
                              maxLength: 40,
                              decoration: const InputDecoration(
                                hintText: 'e.g. Saturday, 8:30 PM',
                                labelText: 'Date / time',
                                counterText: '',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _venueCtrl,
                              maxLength: 40,
                              decoration: const InputDecoration(
                                hintText: 'e.g. eSportlyic Arena',
                                labelText: 'Venue / platform',
                                counterText: '',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _onShare,
                          icon: _busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.ios_share_rounded),
                          label: const Text(
                            'Share Poster',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'The share sheet also lets you save the image to your '
                        'device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.secondaryText(brightness),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _StaticChoiceChip extends StatelessWidget {
  const _StaticChoiceChip({required this.label, required this.selected});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {},
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Glass(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
