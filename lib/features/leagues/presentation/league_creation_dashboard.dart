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

enum LeagueCreationType {
  series,
  group,
  classic,
}

class LeagueCreationDashboard extends ConsumerStatefulWidget {
  const LeagueCreationDashboard({super.key});

  @override
  ConsumerState<LeagueCreationDashboard> createState() => _LeagueCreationDashboardState();
}

class _LeagueCreationDashboardState extends ConsumerState<LeagueCreationDashboard> {
  final Uuid _uuid = const Uuid();

  int _step = 0;

  LeagueCreationType? _type;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

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

  LeagueFormat get _format {
    final type = _type;
    if (type == null) return LeagueFormat.classic;

    switch (type) {
      case LeagueCreationType.series:
        return LeagueFormat.uclSwiss;
      case LeagueCreationType.group:
        return LeagueFormat.uclGroup;
      case LeagueCreationType.classic:
        return LeagueFormat.classic;
    }
  }

  bool get _creationRequiresPayment {
    return _format == LeagueFormat.uclGroup || _format == LeagueFormat.uclSwiss;
  }

  int get _maxTeams {
    switch (_format) {
      case LeagueFormat.classic:
        return 20;
      case LeagueFormat.uclGroup:
      case LeagueFormat.uclSwiss:
        return 36;
    }
  }

  bool get _paymentCompleted => _payment?.success == true;

  String get _typeLabel {
    final type = _type;
    if (type == null) return 'Not selected';
    switch (type) {
      case LeagueCreationType.series:
        return 'Series League';
      case LeagueCreationType.group:
        return 'Group League';
      case LeagueCreationType.classic:
        return 'Classic League';
    }
  }

  IconData get _typeIcon {
    final type = _type;
    if (type == null) return Icons.help_outline;
    switch (type) {
      case LeagueCreationType.series:
        return Icons.auto_graph;
      case LeagueCreationType.group:
        return Icons.grid_view;
      case LeagueCreationType.classic:
        return Icons.table_chart;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;

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
              constraints: BoxConstraints(maxWidth: isWide ? 760 : 520),
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
      body: SafeArea(
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final contentMax = maxWidth >= 1200 ? 1180.0 : (maxWidth >= 900 ? 900.0 : 560.0);

              final left = ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 720 : contentMax),
                child: _buildMainCard(context),
              );

              if (!isWide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMax),
                    child: left,
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: contentMax),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: left),
                      const SizedBox(width: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: _buildSideSummary(context),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMainCard(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStepHeader(context),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _stepBody(context, key: ValueKey<int>(_step)),
          ),
          const SizedBox(height: 16),
          _buildFooterActions(context),
        ],
      ),
    );
  }

  Widget _buildSideSummary(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Summary',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _summaryRow(Icons.auto_awesome, 'Type', _typeLabel),
          _summaryRow(Icons.label, 'Name', _name.text.trim().isEmpty ? 'Not set' : _name.text.trim()),
          _summaryRow(Icons.lock, 'Privacy', _privacy == LeaguePrivacy.private ? 'Private' : 'Public'),
          _summaryRow(Icons.groups, 'Max teams', '$_maxTeams'),
          _summaryRow(
            _creationRequiresPayment ? (_paymentCompleted ? Icons.verified : Icons.lock_outline) : Icons.verified,
            'Creation fee',
            _creationRequiresPayment ? (_paymentCompleted ? 'Paid' : 'Required') : 'Free',
            valueColor: _creationRequiresPayment ? (_paymentCompleted ? Colors.cyanAccent : Colors.orangeAccent) : Colors.cyanAccent,
          ),
          const SizedBox(height: 10),
          Text(
            _creationRequiresPayment
                ? 'Series/Group leagues require payment before creation.'
                : 'Classic league creation is free.',
            style: TextStyle(color: Colors.white.withOpacity(0.60), height: 1.35, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.cyanAccent),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor ?? Colors.white, fontWeight: FontWeight.w700, height: 1.25),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepHeader(BuildContext context) {
    final steps = <_StepMeta>[
      const _StepMeta('Type', Icons.auto_awesome),
      const _StepMeta('Details', Icons.edit_note),
      const _StepMeta('Privacy', Icons.lock),
      const _StepMeta('Payment', Icons.payments_outlined),
      const _StepMeta('Confirm', Icons.check_circle_outline),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'League Creation',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              Expanded(
                child: _stepPill(
                  title: steps[i].title,
                  icon: steps[i].icon,
                  index: i,
                  current: _step,
                ),
              ),
              if (i != steps.length - 1) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (_step + 1) / steps.length,
            minHeight: 8,
            backgroundColor: Colors.white.withOpacity(0.08),
            color: Colors.cyanAccent,
          ),
        ),
      ],
    );
  }

  Widget _stepPill({
    required String title,
    required IconData icon,
    required int index,
    required int current,
  }) {
    final active = index == current;
    final done = index < current;

    final Color borderColor = active
        ? Colors.cyanAccent.withOpacity(0.75)
        : done
            ? Colors.cyanAccent.withOpacity(0.40)
            : Colors.white.withOpacity(0.12);

    final Color bgColor = active
        ? Colors.cyanAccent.withOpacity(0.16)
        : done
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.04);

    final Color iconColor = active
        ? Colors.cyanAccent
        : done
            ? Colors.cyanAccent.withOpacity(0.85)
            : Colors.white54;

    final Color textColor = active
        ? Colors.cyanAccent
        : done
            ? Colors.white70
            : Colors.white54;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody(BuildContext context, {Key? key}) {
    switch (_step) {
      case 0:
        return _stepLeagueType(context, key: key);
      case 1:
        return _stepLeagueDetails(context, key: key);
      case 2:
        return _stepPrivacy(context, key: key);
      case 3:
        return _stepPayment(context, key: key);
      case 4:
        return _stepConfirm(context, key: key);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stepLeagueType(BuildContext context, {Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose one league type. This affects fixtures, qualification, and standings.',
          style: TextStyle(color: Colors.white.withOpacity(0.72), height: 1.35),
        ),
        const SizedBox(height: 14),
        _typeCard(
          type: LeagueCreationType.series,
          title: 'Series League',
          subtitle: 'UCL-style Swiss model.\n36 teams. Best for big competitions.',
          icon: Icons.auto_graph,
        ),
        const SizedBox(height: 10),
        _typeCard(
          type: LeagueCreationType.group,
          title: 'Group League',
          subtitle: 'UCL-style groups.\nGroup-based qualification.',
          icon: Icons.grid_view,
        ),
        const SizedBox(height: 10),
        _typeCard(
          type: LeagueCreationType.classic,
          title: 'Classic League',
          subtitle: 'League table format.\nRound-robin standings.',
          icon: Icons.table_chart,
        ),
      ],
    );
  }

  Widget _typeCard({
    required LeagueCreationType type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _type == type;

    return InkWell(
      onTap: () => setState(() {
        _type = type;
        if (type == LeagueCreationType.classic) {
          _payment = null;
        }
      }),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? Colors.cyanAccent.withOpacity(0.14) : Colors.white.withOpacity(0.04),
          border: Border.all(
            color: selected ? Colors.cyanAccent.withOpacity(0.70) : Colors.white.withOpacity(0.10),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected ? Colors.cyanAccent.withOpacity(0.18) : Colors.white.withOpacity(0.06),
                border: Border.all(
                  color: selected ? Colors.cyanAccent.withOpacity(0.70) : Colors.white.withOpacity(0.10),
                ),
              ),
              child: Icon(icon, color: selected ? Colors.cyanAccent : Colors.white70),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withOpacity(0.70), height: 1.25, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? Colors.cyanAccent : Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                selected ? 'SELECTED' : 'SELECT',
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepLeagueDetails(BuildContext context, {Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('League Details', Icons.edit_note),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: 'League Name (required)',
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: const Icon(Icons.edit_note, color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withOpacity(0.04),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.85)),
            ),
          ),
          onChanged: (_) {
            if (mounted) setState(() {});
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          minLines: 3,
          maxLines: 7,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: 'League Description (recommended)',
            alignLabelWithHint: true,
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: const Icon(Icons.subject, color: Colors.white70),
            filled: true,
            fillColor: Colors.white.withOpacity(0.04),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.85)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _infoBanner(
          icon: _typeIcon,
          title: '$_typeLabel • Max teams $_maxTeams',
          subtitle: 'Format: ${_format.displayName}',
        ),
      ],
    );
  }

  Widget _stepPrivacy(BuildContext context, {Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Privacy', Icons.lock),
        const SizedBox(height: 10),
        _privacyTile(
          value: LeaguePrivacy.public,
          title: 'Public League',
          subtitle: 'Discoverable globally. Anyone can join.',
        ),
        const SizedBox(height: 10),
        _privacyTile(
          value: LeaguePrivacy.private,
          title: 'Private League',
          subtitle: 'Invite-only. Join via code or link (future-compatible).',
        ),
      ],
    );
  }

  Widget _privacyTile({
    required LeaguePrivacy value,
    required String title,
    required String subtitle,
  }) {
    final selected = _privacy == value;

    return InkWell(
      onTap: () => setState(() => _privacy = value),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected ? Colors.cyanAccent.withOpacity(0.14) : Colors.white.withOpacity(0.04),
          border: Border.all(
            color: selected ? Colors.cyanAccent.withOpacity(0.70) : Colors.white.withOpacity(0.10),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? Colors.cyanAccent : Colors.white54,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withOpacity(0.65), height: 1.25, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepPayment(BuildContext context, {Key? key}) {
    if (!_creationRequiresPayment) {
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('Payment', Icons.payments_outlined),
          const SizedBox(height: 10),
          _infoBanner(
            icon: Icons.verified,
            title: 'No payment required',
            subtitle: 'Classic League creation is free.',
            accent: Colors.cyanAccent,
          ),
        ],
      );
    }

    final statusTitle = _paymentCompleted ? 'Payment completed' : 'Payment required';
    final statusSubtitle = _paymentCompleted
        ? 'Receipt: ${_payment?.receiptId ?? ''}'
        : 'You must pay app charges before creating this league.';
    final statusIcon = _paymentCompleted ? Icons.verified : Icons.lock_outline;
    final accent = _paymentCompleted ? Colors.cyanAccent : Colors.orangeAccent;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Payment', Icons.payments_outlined),
        const SizedBox(height: 10),
        _infoBanner(
          icon: statusIcon,
          title: statusTitle,
          subtitle: statusSubtitle,
          accent: accent,
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _submitting
              ? null
              : () async {
                  final name = _name.text.trim().isEmpty ? 'League' : _name.text.trim();
                  final result = await context.push<LeagueCreationPaymentResult?>(
                    '/leagues/create/payment',
                    extra: {'leagueName': name},
                  );
                  if (!mounted) return;

                  if (result != null && result.success) {
                    setState(() => _payment = result);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payment successful')),
                    );
                    return;
                  }

                  if (result == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Payment cancelled')),
                    );
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result.errorMessage ?? 'Payment failed')),
                  );
                },
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(_paymentCompleted ? 'PAYMENT DONE (VIEW RECEIPT)' : 'PAY NOW'),
        ),
      ],
    );
  }

  Widget _stepConfirm(BuildContext context, {Key? key}) {
    final canCreate = _type != null &&
        _name.text.trim().isNotEmpty &&
        (!_creationRequiresPayment || _paymentCompleted);

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Confirm', Icons.check_circle_outline),
        const SizedBox(height: 10),
        _infoBanner(
          icon: _typeIcon,
          title: _typeLabel,
          subtitle: _name.text.trim().isEmpty ? 'League name not set' : _name.text.trim(),
        ),
        const SizedBox(height: 10),
        _confirmRow(Icons.lock, 'Privacy', _privacy == LeaguePrivacy.private ? 'Private' : 'Public'),
        _confirmRow(Icons.groups, 'Max teams', '$_maxTeams'),
        _confirmRow(
          _creationRequiresPayment ? (_paymentCompleted ? Icons.verified : Icons.lock_outline) : Icons.verified,
          'Creation fee',
          _creationRequiresPayment ? (_paymentCompleted ? 'Paid' : 'Required') : 'Free',
          valueColor: _creationRequiresPayment ? (_paymentCompleted ? Colors.cyanAccent : Colors.orangeAccent) : Colors.cyanAccent,
        ),
        const SizedBox(height: 14),
        Text(
          'By creating, you will automatically become League Admin and League Organizer.',
          style: TextStyle(color: Colors.white.withOpacity(0.70), height: 1.35),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: (_submitting || !canCreate) ? null : () => _create(context),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: canCreate ? Colors.cyanAccent : Colors.white24,
            foregroundColor: canCreate ? Colors.black : Colors.white54,
          ),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'CREATE LEAGUE',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
      ],
    );
  }

  Widget _confirmRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.cyanAccent),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor ?? Colors.white, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.cyanAccent.withOpacity(0.14),
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.35)),
          ),
          child: Icon(icon, size: 18, color: Colors.cyanAccent),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ],
    );
  }

  Widget _infoBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    Color? accent,
  }) {
    final a = accent ?? Colors.cyanAccent;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(color: a.withOpacity(0.40)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: a, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withOpacity(0.70), height: 1.25, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context) {
    final isLast = _step == 4;

    final canGoBack = !_submitting;
    final canGoNext = !_submitting;

    final nextLabel = isLast ? 'DONE' : 'NEXT';
    final backLabel = _step == 0 ? 'CANCEL' : 'BACK';

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: !canGoBack
                ? null
                : () {
                    if (_step == 0) {
                      context.pop();
                      return;
                    }
                    setState(() => _step--);
                  },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: Colors.white.withOpacity(0.18)),
              foregroundColor: Colors.white70,
            ),
            child: Text(backLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: !canGoNext
                ? null
                : () async {
                    if (isLast) {
                      if (_createdLeague == null) {
                        context.pop();
                      }
                      return;
                    }
                    final ok = await _validateAndAdvance(context);
                    if (ok) {
                      setState(() => _step++);
                    }
                  },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(nextLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }

  Future<bool> _validateAndAdvance(BuildContext context) async {
    if (_step == 0) {
      if (_type == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a league type')),
        );
        return false;
      }
      return true;
    }

    if (_step == 1) {
      if (_name.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('League name is required')),
        );
        return false;
      }
      return true;
    }

    if (_step == 2) {
      return true;
    }

    if (_step == 3) {
      if (_creationRequiresPayment && !_paymentCompleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complete payment to continue')),
        );
        return false;
      }
      return true;
    }

    return true;
  }

  Future<void> _create(BuildContext context) async {
    if (_type == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a league type')),
      );
      return;
    }

    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('League name is required')),
      );
      return;
    }

    if (_creationRequiresPayment && !_paymentCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment must be completed before creating the league')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final prefs = ref.read(prefsServiceProvider);
      final repo = LocalLeaguesRepository(prefs);

      final organizerUserId = await CurrentUser.getOrCreateUserId();

      final leagueId = _uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      final settings = LeagueSettings.defaultsFor(_format).copyWith(
        lastPulledAtMs: 0,
      );

      final league = League(
        id: leagueId,
        name: _name.text.trim(),
        description: _description.text.trim(),
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

      final stored = await repo.createLeagueLocally(
        league: league,
        organizerUserId: organizerUserId,
      );

      if (!mounted) return;
      setState(() {
        _createdLeague = stored;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create league: $e')),
      );
    }
  }
}

class _StepMeta {
  final String title;
  final IconData icon;

  const _StepMeta(this.title, this.icon);
}
