import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/persistence/prefs_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/league_flip_card.dart';
import '../data/leagues_repository_local.dart';
import '../models/enums.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';

class LeagueCreateWizard extends ConsumerStatefulWidget {
  const LeagueCreateWizard({super.key});

  @override
  ConsumerState<LeagueCreateWizard> createState() => _LeagueCreateWizardState();
}

class _LeagueCreateWizardState extends ConsumerState<LeagueCreateWizard> {
  final _uuid = const Uuid();
  int _step = 0;

  final _name = TextEditingController();
  LeagueFormat _format = LeagueFormat.classic;

  LeaguePrivacy _privacy = LeaguePrivacy.private;

  bool _doubleRoundRobin = true;
  bool _submitting = false;

  League? _createdLeague;

  int get _maxTeams {
    switch (_format) {
      case LeagueFormat.classic:
        return 20;
      case LeagueFormat.uclGroup:
      case LeagueFormat.uclSwiss:
        return 32;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;

    if (_createdLeague != null) {
      final league = _createdLeague!;
      return GlassScaffold(
        appBar: AppBar(
          title: const Text('League Created'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 600 : 450),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LeagueFlipCard(
                    leagueName: league.name,
                    leagueCode: league.code,
                    distribution: '${league.format.displayName} • ${league.season}',
                    subtitle: '0 / ${league.maxTeams} teams',
                    onDoubleTap: () => context.push('/leagues/${league.id}'),
                    qrWidget: QrImageView(
                      data: league.qrPayload,
                      version: QrVersions.auto,
                      gapless: true,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Colors.black,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Glass(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Share this Join ID or let others scan the QR on the back of the card.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.75), height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () => context.go('/leagues'),
                                child: const Text('DONE'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => context.push(
                                  '/leagues/add-teams',
                                  extra: {'leagueId': league.id, 'format': league.format},
                                ),
                                child: const Text('ADD TEAMS'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.push('/leagues/${league.id}'),
                          child: const Text(
                            'OPEN LEAGUE DETAILS',
                            style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                          ),
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
    }

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Create League'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isWide ? 600 : 450),
              child: Glass(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    colorScheme: Theme.of(context).colorScheme.copyWith(
                          onSurface: Colors.white,
                          primary: Colors.cyanAccent,
                        ),
                    dividerColor: Colors.white24,
                  ),
                  child: Stepper(
                    physics: const NeverScrollableScrollPhysics(),
                    currentStep: _step,
                    controlsBuilder: (context, details) {
                      final isLast = _step == 2;
                      return Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _submitting
                                  ? null
                                  : () {
                                      if (_step == 0) {
                                        context.pop();
                                      } else {
                                        setState(() => _step--);
                                      }
                                    },
                              child: Text(_step == 0 ? 'Cancel' : 'Back'),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              onPressed: _submitting
                                  ? null
                                  : () async {
                                      if (isLast) {
                                        await _create(context);
                                      } else {
                                        if (_step == 0 && _name.text.trim().isEmpty) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Please enter a league name')),
                                          );
                                          return;
                                        }
                                        setState(() => _step++);
                                      }
                                    },
                              child: _submitting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text(isLast ? 'Create' : 'Next'),
                            ),
                          ],
                        ),
                      );
                    },
                    steps: [
                      Step(title: const Text('Basics'), content: _basicsStep(), isActive: _step >= 0),
                      Step(title: const Text('Rules'), content: _rulesStep(), isActive: _step >= 1),
                      Step(title: const Text('Review'), content: _reviewStep(), isActive: _step >= 2),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _basicsStep() {
    return Column(
      children: [
        TextField(
          controller: _name,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'League name',
            prefixIcon: Icon(Icons.edit_note, color: Colors.white70),
          ),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<LeagueFormat>(
          value: _format,
          dropdownColor: const Color(0xFF0A1D37),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Tournament Format'),
          items: const [
            DropdownMenuItem(value: LeagueFormat.classic, child: Text('Round Robin')),
            DropdownMenuItem(value: LeagueFormat.uclGroup, child: Text('UCL Groups + Knockout')),
            DropdownMenuItem(value: LeagueFormat.uclSwiss, child: Text('UCL Swiss Model')),
          ],
          onChanged: (v) => setState(() => _format = v!),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<LeaguePrivacy>(
          value: _privacy,
          dropdownColor: const Color(0xFF0A1D37),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Privacy'),
          items: const [
            DropdownMenuItem(value: LeaguePrivacy.private, child: Text('Private (members only)')),
            DropdownMenuItem(value: LeaguePrivacy.public, child: Text('Public (visible to everyone)')),
          ],
          onChanged: (v) => setState(() => _privacy = v ?? LeaguePrivacy.private),
        ),
      ],
    );
  }

  Widget _rulesStep() {
    return Column(
      children: [
        CheckboxListTile(
          value: _doubleRoundRobin,
          activeColor: Colors.cyanAccent,
          onChanged: (v) => setState(() => _doubleRoundRobin = v ?? true),
          title: const Text('Double Round Robin', style: TextStyle(color: Colors.white)),
          subtitle: const Text(
            'Home & Away legs (if applicable)',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _reviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow(Icons.label, 'Name', _name.text),
        _infoRow(Icons.format_list_bulleted, 'Format', _format.displayName),
        _infoRow(Icons.lock, 'Privacy', _privacy == LeaguePrivacy.private ? 'Private' : 'Public'),
        _infoRow(Icons.groups, 'Max Teams', '$_maxTeams'),
        _infoRow(Icons.repeat, 'Double Round Robin', _doubleRoundRobin ? 'Yes' : 'No'),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.cyanAccent),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    if (_name.text.trim().isEmpty) return;

    setState(() => _submitting = true);

    final prefs = ref.read(prefsServiceProvider);
    final repo = LocalLeaguesRepository(prefs);

    final organizerUserId = prefs.getCurrentUserId() ?? 'admin_user';

    final leagueId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    final settings = LeagueSettings.defaultsFor(_format).copyWith(
      doubleRoundRobin: _doubleRoundRobin,
      lastPulledAtMs: 0,
    );

    final league = League(
      id: leagueId,
      name: _name.text.trim(),
      format: _format,
      privacy: _privacy,
      region: 'Global',
      maxTeams: _maxTeams,
      season: '2026',
      organizerUserId: organizerUserId,
      code: '',
      qrPayloadOverride: '',
      settings: settings,
      updatedAtMs: now,
      version: 1,
    );

    await Future.delayed(const Duration(milliseconds: 250));

    final stored = await repo.createLeagueLocally(
      league: league,
      organizerUserId: organizerUserId,
    );

    if (!mounted) return;
    setState(() {
      _createdLeague = stored;
      _submitting = false;
    });
  }
}
