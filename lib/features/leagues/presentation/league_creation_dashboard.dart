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
import '../logic/league_creation_payment_service.dart';
import '../models/enums.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import '../utils/current_user.dart';

enum LeagueCreationType { series, group, classic }

class LeagueCreationDashboard extends ConsumerStatefulWidget {
  const LeagueCreationDashboard({super.key});

  @override
  ConsumerState<LeagueCreationDashboard> createState() => _LeagueCreationDashboardState();
}

class _LeagueCreationDashboardState extends ConsumerState<LeagueCreationDashboard> {
  final Uuid _uuid = const Uuid();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  
  int _step = 0;
  LeagueCreationType? _type;
  LeaguePrivacy _privacy = LeaguePrivacy.private;
  LeagueCreationPaymentResult? _payment;
  bool _submitting = false;
  League? _createdLeague;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  // --- Getters ---

  LeagueFormat get _format {
    switch (_type) {
      case LeagueCreationType.series: return LeagueFormat.uclSwiss;
      case LeagueCreationType.group: return LeagueFormat.uclGroup;
      case LeagueCreationType.classic:
      default: return LeagueFormat.classic;
    }
  }

  int get _maxTeams {
    return (_format == LeagueFormat.classic) ? 20 : 36;
  }

  bool get _paymentCompleted => _payment?.success == true;

  // --- Main Build ---

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 600;

    return GlassScaffold(
      appBar: AppBar(
        title: Text(_createdLeague != null ? 'League Created' : 'Create League'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: _createdLeague != null 
            ? _buildSuccessView(context, isWide) 
            : _buildStepperView(context, isWide),
      ),
    );
  }

  // --- View Components ---

  Widget _buildSuccessView(BuildContext context, bool isWide) {
    final league = _createdLeague!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 640 : 480),
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
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
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
    );
  }

  Widget _buildStepperView(BuildContext context, bool isWide) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWide ? 700 : 520),
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
                controlsBuilder: (context, details) => _buildStepperControls(context),
                steps: [
                  Step(title: const Text('League Type'), content: _stepLeagueType(context), isActive: _step >= 0),
                  Step(title: const Text('League Details'), content: _stepLeagueDetails(context), isActive: _step >= 1),
                  Step(title: const Text('Privacy'), content: _stepPrivacy(context), isActive: _step >= 2),
                  Step(title: const Text('Payment'), content: _stepPayment(context), isActive: _step >= 3),
                  Step(title: const Text('Confirm & Create'), content: _stepConfirm(context), isActive: _step >= 4),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepperControls(BuildContext context) {
    final isLast = _step == 4;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _submitting ? null : () {
              if (_step == 0) context.pop();
              else setState(() => _step--);
            },
            child: Text(_step == 0 ? 'Cancel' : 'Back'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _submitting ? null : () async {
              if (isLast) {
                await _create(context);
              } else {
                if (await _validateAndAdvance(context)) setState(() => _step++);
              }
            },
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(isLast ? 'Create League' : 'Next'),
          ),
        ],
      ),
    );
  }

  // --- Step Content Widgets ---

  Widget _stepLeagueType(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose one league type. This affects fixtures, qualification, and standings.',
          style: TextStyle(color: Colors.white.withOpacity(0.75), height: 1.35),
        ),
        const SizedBox(height: 14),
        _typeCard(
          context: context,
          type: LeagueCreationType.series,
          title: 'Series League (UCL)',
          subtitle: '36 teams, Swiss model league phase leading into qualification.',
          icon: Icons.auto_graph,
        ),
        const SizedBox(height: 10),
        _typeCard(
          context: context,
          type: LeagueCreationType.group,
          title: 'Group League (UCL)',
          subtitle: 'Teams split into groups. Top teams advance to knockouts.',
          icon: Icons.grid_view,
        ),
        const SizedBox(height: 10),
        _typeCard(
          context: context,
          type: LeagueCreationType.classic,
          title: 'Classic League',
          subtitle: 'Traditional round-robin standings (e.g., Premier League).',
          icon: Icons.table_chart,
        ),
      ],
    );
  }

  Widget _typeCard({
    required BuildContext context,
    required LeagueCreationType type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _type == type;
    return InkWell(
      onTap: () => setState(() => _type = type),
      borderRadius: BorderRadius.circular(18),
      child: Glass(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: selected ? Colors.cyanAccent.withOpacity(0.18) : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? Colors.cyanAccent.withOpacity(0.75) : Colors.white.withOpacity(0.10)),
              ),
              child: Icon(icon, color: selected ? Colors.cyanAccent : Colors.white70),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      if (selected) const Icon(Icons.check_circle, color: Colors.cyanAccent, size: 18),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.70), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepLeagueDetails(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _name,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'League Name (required)', prefixIcon: Icon(Icons.edit_note)),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _description,
          minLines: 3, maxLines: 6,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Description (recommended)', alignLabelWithHint: true, prefixIcon: Icon(Icons.subject)),
        ),
        const SizedBox(height: 12),
        _infoLine(icon: Icons.groups, label: 'Max Teams', value: '$_maxTeams'),
      ],
    );
  }

  Widget _stepPrivacy(BuildContext context) {
    return Column(
      children: [
        RadioListTile<LeaguePrivacy>(
          value: LeaguePrivacy.public, groupValue: _privacy,
          activeColor: Colors.cyanAccent,
          onChanged: (v) => setState(() => _privacy = v!),
          title: const Text('Public', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Discoverable by anyone.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        RadioListTile<LeaguePrivacy>(
          value: LeaguePrivacy.private, groupValue: _privacy,
          activeColor: Colors.cyanAccent,
          onChanged: (v) => setState(() => _privacy = v!),
          title: const Text('Private', style: TextStyle(color: Colors.white)),
          subtitle: const Text('Invite-only via code.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _stepPayment(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoLine(
          icon: _paymentCompleted ? Icons.verified : Icons.warning,
          label: 'Status',
          value: _paymentCompleted ? 'Paid' : 'Payment Required',
          valueColor: _paymentCompleted ? Colors.cyanAccent : Colors.orangeAccent,
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () async {
              final res = await context.push<LeagueCreationPaymentResult?>('/leagues/create/payment');
              if (res?.success == true) setState(() => _payment = res);
            },
            child: Text(_paymentCompleted ? 'Payment Verified' : 'Pay Creation Fee'),
          ),
        ),
      ],
    );
  }

  Widget _stepConfirm(BuildContext context) {
    return Column(
      children: [
        _infoLine(icon: Icons.auto_awesome, label: 'Type', value: _format.displayName),
        _infoLine(icon: Icons.label, label: 'Name', value: _name.text),
        _infoLine(icon: Icons.lock, label: 'Privacy', value: _privacy.name.toUpperCase()),
        _infoLine(icon: Icons.payments, label: 'Payment', value: _paymentCompleted ? 'Success' : 'Pending'),
      ],
    );
  }

  Widget _infoLine({required IconData icon, required String label, required String value, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.cyanAccent),
          const SizedBox(width: 12),
          Text('$label: ', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, style: TextStyle(color: valueColor ?? Colors.white))),
        ],
      ),
    );
  }

  // --- Logic ---

  Future<bool> _validateAndAdvance(BuildContext context) async {
    if (_step == 0 && _type == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a league type')));
      return false;
    }
    if (_step == 1 && _name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name is required')));
      return false;
    }
    if (_step == 3 && !_paymentCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment required')));
      return false;
    }
    return true;
  }

  Future<void> _create(BuildContext context) async {
    setState(() => _submitting = true);
    try {
      final prefs = ref.read(prefsServiceProvider);
      final repo = LocalLeaguesRepository(prefs);
      final userId = await CurrentUser.getOrCreateUserId();
      
      final league = League(
        id: _uuid.v4(),
        name: _name.text.trim(),
        description: _description.text.trim(),
        format: _format,
        privacy: _privacy,
        region: 'Global',
        maxTeams: _maxTeams,
        season: '2026',
        organizerUserId: userId,
        code: '',
        qrPayloadOverride: '',
        settings: LeagueSettings.defaultsFor(_format),
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        version: 1,
      );

      final stored = await repo.createLeagueLocally(league: league, organizerUserId: userId);
      setState(() {
        _createdLeague = stored;
        _submitting = false;
      });
    } catch (e) {
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
