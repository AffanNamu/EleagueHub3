import '../utils/current_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/locale/app_localizations.dart';
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

class LeagueCreateWizard extends ConsumerStatefulWidget {
  const LeagueCreateWizard({super.key});

  @override
  ConsumerState<LeagueCreateWizard> createState() => _LeagueCreateWizardState();
}

class _LeagueCreateWizardState extends ConsumerState<LeagueCreateWizard> {
  final _uuid = const Uuid();
  int _step = 0;

  final _name = TextEditingController();
  final _description = TextEditingController();

  LeagueFormat _format = LeagueFormat.classic;
  LeaguePrivacy _privacy = LeaguePrivacy.private;

  bool _doubleRoundRobin = true;
  bool _submitting = false;

  LeagueCreationPaymentResult? _payment;

  League? _createdLeague;

  int get _maxTeams {
    switch (_format) {
      case LeagueFormat.classic:
        return 20;
      case LeagueFormat.uclGroup:
      case LeagueFormat.uclSwiss:
        return 36;
    }
  }

  bool get _creationRequiresPayment {
    return _format == LeagueFormat.uclGroup || _format == LeagueFormat.uclSwiss;
  }

  bool get _paymentCompleted => _payment?.success == true;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  String _formatLabel(AppLocalizations l10n) {
    switch (_format) {
      case LeagueFormat.classic:
        return l10n.tr('league_create_type_classic_title');
      case LeagueFormat.uclGroup:
        return l10n.tr('league_create_type_group_title');
      case LeagueFormat.uclSwiss:
        return l10n.tr('league_create_type_series_title');
    }
  }

  String _privacyLabel(AppLocalizations l10n) {
    return _privacy == LeaguePrivacy.private ? l10n.tr('league_create_private') : l10n.tr('league_create_public');
  }

  String _creationFeeLabel(AppLocalizations l10n) {
    if (!_creationRequiresPayment) return l10n.tr('league_create_fee_free');
    return _paymentCompleted ? l10n.tr('league_create_fee_paid') : l10n.tr('league_create_fee_required');
  }

  String _unlockNote(AppLocalizations l10n) {
    return _creationRequiresPayment ? l10n.tr('league_create_fee_note_requires_payment') : l10n.tr('league_create_fee_note_free');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;

    if (_createdLeague != null) {
      final league = _createdLeague!;
      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('league_create_created_title')),
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
                    subtitle: '0 / ${league.maxTeams} ${l10n.tr('league_create_teams_word')}',
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
                          l10n.tr('league_create_share_hint'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white.withOpacity(0.75), height: 1.4),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton(
                                onPressed: () => context.go('/leagues'),
                                child: Text(l10n.tr('league_create_done_upper')),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => context.push(
                                  '/leagues/add-teams',
                                  extra: {'leagueId': league.id, 'format': league.format},
                                ),
                                child: Text(l10n.tr('league_create_add_teams_upper')),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => context.push('/leagues/${league.id}'),
                          child: Text(
                            l10n.tr('league_create_open_league_details_upper'),
                            style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold),
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
        title: Text(l10n.tr('league_create_appbar_title')),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final contentMax = maxWidth >= 1200 ? 1180.0 : (maxWidth >= 900 ? 900.0 : 560.0);

              final main = ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 720 : contentMax),
                child: _buildMainCard(context),
              );

              if (!isWide) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMax),
                    child: main,
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
                      Expanded(child: main),
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
          _buildStepHeader(),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _stepBody(key: ValueKey<int>(_step)),
          ),
          const SizedBox(height: 16),
          _buildFooterActions(context),
        ],
      ),
    );
  }

  Widget _buildSideSummary(BuildContext context) {
    final l10n = context.l10n;

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('league_create_summary_title'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _summaryRow(Icons.format_list_bulleted, l10n.tr('league_create_summary_type_label'), _formatLabel(l10n)),
          _summaryRow(
            Icons.label,
            l10n.tr('league_create_summary_name_label'),
            _name.text.trim().isEmpty ? l10n.tr('league_create_summary_not_set') : _name.text.trim(),
          ),
          _summaryRow(Icons.lock, l10n.tr('league_create_summary_privacy_label'), _privacyLabel(l10n)),
          _summaryRow(Icons.groups, l10n.tr('league_create_summary_max_teams_label'), '$_maxTeams'),
          _summaryRow(
            Icons.repeat,
            l10n.tr('league_create_wizard_double_rr_label'),
            _doubleRoundRobin ? l10n.tr('common_yes') : l10n.tr('common_no'),
          ),
          _summaryRow(
            _creationRequiresPayment ? (_paymentCompleted ? Icons.verified : Icons.lock_outline) : Icons.verified,
            l10n.tr('league_create_summary_creation_fee_label'),
            _creationFeeLabel(l10n),
            valueColor: _creationRequiresPayment
                ? (_paymentCompleted ? Colors.cyanAccent : Colors.orangeAccent)
                : Colors.cyanAccent,
          ),
          const SizedBox(height: 10),
          Text(
            _unlockNote(l10n),
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

  Widget _buildStepHeader() {
    final l10n = context.l10n;

    final steps = <_StepMeta>[
      _StepMeta(l10n.tr('league_create_wizard_step_basics'), Icons.edit_note),
      _StepMeta(l10n.tr('league_create_wizard_step_rules'), Icons.rule),
      _StepMeta(l10n.tr('league_create_wizard_step_review'), Icons.check_circle_outline),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.tr('league_create_header_title'),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
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
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepBody({Key? key}) {
    switch (_step) {
      case 0:
        return _basicsStep(key: key);
      case 1:
        return _rulesStep(key: key);
      case 2:
        return _reviewStep(key: key);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _basicsStep({Key? key}) {
    final l10n = context.l10n;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_wizard_step_basics'), Icons.edit_note),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: l10n.tr('league_create_league_name_required_label'),
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
            labelText: l10n.tr('league_create_league_description_recommended_label'),
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
        DropdownButtonFormField<LeagueFormat>(
          value: _format,
          dropdownColor: const Color(0xFF0A1D37),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: l10n.tr('league_create_wizard_tournament_format_label'),
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: const Icon(Icons.format_list_bulleted, color: Colors.white70),
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
          items: [
            DropdownMenuItem(value: LeagueFormat.classic, child: Text(l10n.tr('league_create_type_classic_title'))),
            DropdownMenuItem(value: LeagueFormat.uclGroup, child: Text(l10n.tr('league_create_type_group_title'))),
            DropdownMenuItem(value: LeagueFormat.uclSwiss, child: Text(l10n.tr('league_create_type_series_title'))),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _format = v;
              _payment = null;
            });
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<LeaguePrivacy>(
          value: _privacy,
          dropdownColor: const Color(0xFF0A1D37),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: l10n.tr('league_create_privacy_title'),
            labelStyle: const TextStyle(color: Colors.white70),
            prefixIcon: const Icon(Icons.lock, color: Colors.white70),
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
          items: [
            DropdownMenuItem(value: LeaguePrivacy.private, child: Text(l10n.tr('league_create_private_title'))),
            DropdownMenuItem(value: LeaguePrivacy.public, child: Text(l10n.tr('league_create_public_title'))),
          ],
          onChanged: (v) => setState(() => _privacy = v ?? LeaguePrivacy.private),
        ),
        const SizedBox(height: 12),
        _infoBanner(
          icon: Icons.groups,
          title: '${l10n.tr('league_create_info_type_max_teams_prefix')} $_maxTeams',
          subtitle: '${l10n.tr('league_create_info_format_prefix')} ${_formatLabel(l10n)}',
          accent: Colors.cyanAccent,
        ),
      ],
    );
  }

  Widget _rulesStep({Key? key}) {
    final l10n = context.l10n;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_wizard_step_rules'), Icons.rule),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withOpacity(0.04),
            border: Border.all(color: Colors.white.withOpacity(0.10)),
          ),
          child: SwitchListTile.adaptive(
            value: _doubleRoundRobin,
            onChanged: (v) => setState(() => _doubleRoundRobin = v),
            activeColor: Colors.cyanAccent,
            title: Text(
              l10n.tr('league_create_wizard_double_round_robin_title'),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              l10n.tr('league_create_wizard_double_round_robin_subtitle'),
              style: TextStyle(color: Colors.white.withOpacity(0.60), fontSize: 12),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 12),
        _infoBanner(
          icon: _creationRequiresPayment ? Icons.lock_outline : Icons.verified,
          title: _creationRequiresPayment ? l10n.tr('league_create_payment_required_title') : l10n.tr('league_create_no_payment_required_title'),
          subtitle: _creationRequiresPayment ? l10n.tr('league_create_payment_required_subtitle') : l10n.tr('league_create_no_payment_required_subtitle'),
          accent: _creationRequiresPayment ? Colors.orangeAccent : Colors.cyanAccent,
        ),
      ],
    );
  }

  Widget _reviewStep({Key? key}) {
    final l10n = context.l10n;

    final canPay = _creationRequiresPayment && _name.text.trim().isNotEmpty;
    final canCreate = _name.text.trim().isNotEmpty && (!_creationRequiresPayment || _paymentCompleted);

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_wizard_step_review'), Icons.check_circle_outline),
        const SizedBox(height: 10),
        _reviewRow(Icons.label, l10n.tr('league_create_summary_name_label'), _name.text.trim().isEmpty ? l10n.tr('league_create_summary_not_set') : _name.text.trim()),
        _reviewRow(Icons.subject, l10n.tr('league_create_wizard_description_label'), _description.text.trim().isEmpty ? l10n.tr('common_none') : _description.text.trim()),
        _reviewRow(Icons.format_list_bulleted, l10n.tr('league_create_summary_type_label'), _formatLabel(l10n)),
        _reviewRow(Icons.lock, l10n.tr('league_create_summary_privacy_label'), _privacyLabel(l10n)),
        _reviewRow(Icons.groups, l10n.tr('league_create_summary_max_teams_label'), '$_maxTeams'),
        _reviewRow(Icons.repeat, l10n.tr('league_create_wizard_double_rr_label'), _doubleRoundRobin ? l10n.tr('common_yes') : l10n.tr('common_no')),
        const SizedBox(height: 10),
        _infoBanner(
          icon: !_creationRequiresPayment
              ? Icons.verified
              : (_paymentCompleted ? Icons.verified : Icons.lock_outline),
          title: !_creationRequiresPayment
              ? '${l10n.tr('league_create_summary_creation_fee_label')}: ${l10n.tr('league_create_fee_free')}'
              : (_paymentCompleted ? '${l10n.tr('league_create_summary_creation_fee_label')}: ${l10n.tr('league_create_fee_paid')}' : '${l10n.tr('league_create_summary_creation_fee_label')}: ${l10n.tr('league_create_fee_required')}'),
          subtitle: !_creationRequiresPayment
              ? l10n.tr('league_create_fee_note_free')
              : (_paymentCompleted ? '${l10n.tr('league_create_receipt_prefix')} ${_payment?.receiptId ?? ''}' : l10n.tr('league_create_error_complete_payment_to_continue')),
          accent: !_creationRequiresPayment
              ? Colors.cyanAccent
              : (_paymentCompleted ? Colors.cyanAccent : Colors.orangeAccent),
        ),
        if (_creationRequiresPayment) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: (_submitting || !canPay)
                ? null
                : () async {
                    final leagueName = _name.text.trim();
                    final result = await context.push<LeagueCreationPaymentResult?>(
                      '/leagues/create/payment',
                      extra: {'leagueName': leagueName},
                    );
                    if (!mounted) return;

                    if (result != null && result.success) {
                      setState(() => _payment = result);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.tr('league_create_payment_successful'))),
                      );
                      return;
                    }

                    if (result == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.tr('league_create_payment_cancelled'))),
                      );
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result.errorMessage ?? l10n.tr('leagues_payment_failed'))),
                    );
                  },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(_paymentCompleted ? l10n.tr('league_create_payment_done_view_receipt') : l10n.tr('league_create_pay_now')),
          ),
        ],
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(
                  l10n.tr('league_create_create_league_button_upper'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
        ),
      ],
    );
  }

  Widget _reviewRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.cyanAccent),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, height: 1.25),
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
    final l10n = context.l10n;
    final isLast = _step == 2;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _submitting
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
            child: Text(_step == 0 ? l10n.tr('common_cancel') : l10n.tr('common_back'), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: _submitting
                ? null
                : () async {
                    if (isLast) return;

                    if (_step == 0 && _name.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.tr('league_create_error_name_required'))),
                      );
                      return;
                    }

                    setState(() => _step++);
                  },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(isLast ? l10n.tr('common_done') : l10n.tr('common_next'), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final l10n = context.l10n;

    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_create_error_name_required'))),
      );
      return;
    }

    if (_creationRequiresPayment && !_paymentCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_create_error_payment_must_be_completed'))),
      );
      return;
    }

    setState(() => _submitting = true);

    final prefs = ref.read(prefsServiceProvider);
    final repo = LocalLeaguesRepository(prefs);

    final organizerUserId = await CurrentUser.getOrCreateUserId();

    final leagueId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;

    final settings = LeagueSettings.defaultsFor(_format).copyWith(
      doubleRoundRobin: _doubleRoundRobin,
      lastPulledAtMs: 0,
    );

    final league = League(
      id: leagueId,
      name: _name.text.trim(),
      description: _description.text.trim(),
      format: _format,
      privacy: _privacy,
      region: l10n.tr('common_region_global'),
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

class _StepMeta {
  final String title;
  final IconData icon;

  const _StepMeta(this.title, this.icon);
}
