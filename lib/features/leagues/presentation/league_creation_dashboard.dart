import 'dart:math';

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
import '../../auth/data/user_profile_repository.dart';
import '../data/leagues_repository_local.dart';
import '../logic/league_creation_payment_service.dart';
import '../models/enums.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import '../models/team.dart';
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

  int? _selectedMaxTeams;

  bool _creatorWillParticipate = false;

  static const Color _premiumAmber = Color(0xFFF59E0B);

  static const List<String> _groupNames = <String>[
    'Group A',
    'Group B',
    'Group C',
    'Group D',
    'Group E',
    'Group F',
    'Group G',
    'Group H',
  ];

  String _pickRandomGroupNameForMaxTeams(int maxTeams) {
    final rnd = Random.secure();
    final groupCount = (maxTeams ~/ 4).clamp(1, 8);
    final names = _groupNames.take(groupCount).toList();
    return names[rnd.nextInt(names.length)];
  }

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

  List<int> get _allowedMaxTeams {
    switch (_format) {
      case LeagueFormat.uclGroup:
        return const [16, 32];
      case LeagueFormat.uclSwiss:
        return const [18, 36];
      case LeagueFormat.classic:
      default:
        return const [20];
    }
  }

  int get _maxTeams {
    final selected = _selectedMaxTeams;
    if (selected != null) return selected;

    switch (_format) {
      case LeagueFormat.classic:
        return 20;
      case LeagueFormat.uclGroup:
        return 32;
      case LeagueFormat.uclSwiss:
        return 36;
    }
  }

  bool get _paymentCompleted => _payment?.success == true;

  String get _typeLabel {
    final l10n = AppLocalizations.of(context);
    final type = _type;
    if (type == null) return l10n.tr('league_create_summary_not_selected');

    switch (type) {
      case LeagueCreationType.series:
        return l10n.tr('league_create_type_series_title');
      case LeagueCreationType.group:
        return l10n.tr('league_create_type_group_title');
      case LeagueCreationType.classic:
        return l10n.tr('league_create_type_classic_title');
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

  void _setType(LeagueCreationType t) {
    setState(() {
      _type = t;

      if (t == LeagueCreationType.classic) {
        _payment = null;
      }

      final fmt = _format;
      if (fmt == LeagueFormat.uclGroup) {
        _selectedMaxTeams = 32;
      } else if (fmt == LeagueFormat.uclSwiss) {
        _selectedMaxTeams = 36;
      } else {
        _selectedMaxTeams = 20;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 760 : 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LeagueFlipCard(
                      leagueName: league.name,
                      leagueCode: league.code,
                      distribution: '${league.format.displayName} • ${league.season}',
                      subtitle: '0 / ${league.maxTeams} ${l10n.tr('leagues_teams_word')}',
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
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.75),
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
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
                              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900),
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

              final left = ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 720 : contentMax),
                child: _buildMainCard(context),
              );

              if (!isWide) {
                return SingleChildScrollView(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: contentMax),
                    child: left,
                  ),
                );
              }

              return SingleChildScrollView(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16),
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final paymentColor = _creationRequiresPayment
        ? (_paymentCompleted ? cs.primary : _premiumAmber)
        : cs.primary;

    return Glass(
      padding: const EdgeInsets.all(16),
      borderRadius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.tr('league_create_summary_title'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          _summaryRow(Icons.auto_awesome, l10n.tr('league_create_summary_type_label'), _typeLabel),
          _summaryRow(
            Icons.label,
            l10n.tr('league_create_summary_name_label'),
            _name.text.trim().isEmpty ? l10n.tr('league_create_summary_not_set') : _name.text.trim(),
          ),
          _summaryRow(
            Icons.lock,
            l10n.tr('league_create_summary_privacy_label'),
            _privacy == LeaguePrivacy.private ? l10n.tr('league_create_private') : l10n.tr('league_create_public'),
          ),
          _summaryRow(Icons.groups, l10n.tr('league_create_summary_max_teams_label'), '$_maxTeams'),
          _summaryRow(
            _creationRequiresPayment ? (_paymentCompleted ? Icons.verified : Icons.lock_outline) : Icons.verified,
            l10n.tr('league_create_summary_creation_fee_label'),
            _creationRequiresPayment
                ? (_paymentCompleted ? l10n.tr('league_create_fee_paid') : l10n.tr('league_create_fee_required'))
                : l10n.tr('league_create_fee_free'),
            valueColor: paymentColor,
          ),
          const SizedBox(height: 10),
          Text(
            _creationRequiresPayment
                ? l10n.tr('league_create_fee_note_requires_payment')
                : l10n.tr('league_create_fee_note_free'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.60),
              height: 1.35,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: valueColor ?? cs.onSurface,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepHeader(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final steps = <_StepMeta>[
      _StepMeta(l10n.tr('league_create_step_type'), Icons.auto_awesome),
      _StepMeta(l10n.tr('league_create_step_details'), Icons.edit_note),
      _StepMeta(l10n.tr('league_create_step_privacy'), Icons.lock),
      _StepMeta(l10n.tr('league_create_step_payment'), Icons.payments_outlined),
      _StepMeta(l10n.tr('league_create_step_confirm'), Icons.check_circle_outline),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.tr('league_create_header_title'),
          style: theme.textTheme.titleLarge?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (int i = 0; i < steps.length; i++) ...[
              Expanded(child: _stepPill(title: steps[i].title, icon: steps[i].icon, index: i, current: _step)),
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
            backgroundColor: cs.onSurface.withOpacity(0.08),
            color: cs.primary,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final active = index == current;
    final done = index < current;

    final Color borderColor = active
        ? cs.primary.withOpacity(0.75)
        : done
            ? cs.primary.withOpacity(0.40)
            : cs.onSurface.withOpacity(0.14);

    final Color bgColor = active
        ? cs.primary.withOpacity(0.14)
        : done
            ? cs.onSurface.withOpacity(0.06)
            : cs.onSurface.withOpacity(0.04);

    final Color iconColor = active
        ? cs.primary
        : done
            ? cs.primary.withOpacity(0.85)
            : cs.onSurface.withOpacity(0.55);

    final Color textColor = active
        ? cs.primary
        : done
            ? cs.onSurface.withOpacity(0.75)
            : cs.onSurface.withOpacity(0.55);

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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.tr('league_create_choose_type_help'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurface.withOpacity(0.72),
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        _typeCard(
          type: LeagueCreationType.series,
          title: l10n.tr('league_create_type_series_title'),
          subtitle: l10n.tr('league_create_type_series_subtitle'),
          icon: Icons.auto_graph,
        ),
        const SizedBox(height: 10),
        _typeCard(
          type: LeagueCreationType.group,
          title: l10n.tr('league_create_type_group_title'),
          subtitle: l10n.tr('league_create_type_group_subtitle'),
          icon: Icons.grid_view,
        ),
        const SizedBox(height: 10),
        _typeCard(
          type: LeagueCreationType.classic,
          title: l10n.tr('league_create_type_classic_title'),
          subtitle: l10n.tr('league_create_type_classic_subtitle'),
          icon: Icons.table_chart,
        ),
        const SizedBox(height: 14),
        if (_type != null && _allowedMaxTeams.length > 1) ...[
          _sectionTitle(l10n.tr('league_create_competition_size_title'), Icons.groups),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final n in _allowedMaxTeams)
                ChoiceChip(
                  label: Text(
                    '$n ${l10n.tr('league_create_teams_word')}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  selected: _maxTeams == n,
                  selectedColor: cs.primary.withOpacity(0.18),
                  backgroundColor: cs.onSurface.withOpacity(0.06),
                  labelStyle: TextStyle(
                    color: _maxTeams == n ? cs.primary : cs.onSurface.withOpacity(0.72),
                    fontWeight: _maxTeams == n ? FontWeight.w900 : FontWeight.w800,
                  ),
                  onSelected: (v) {
                    if (!v) return;
                    setState(() => _selectedMaxTeams = n);
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _format == LeagueFormat.uclGroup
                ? '${l10n.tr('league_create_groups_will_be_prefix')} ${_maxTeams ~/ 4} ${l10n.tr('league_create_groups_will_be_suffix')}'
                : '${l10n.tr('league_create_swiss_table_prefix')} $_maxTeams ${l10n.tr('league_create_swiss_table_suffix')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.55),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _typeCard({
    required LeagueCreationType type,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final selected = _type == type;

    return InkWell(
      onTap: () => _setType(type),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected ? cs.primary.withOpacity(0.14) : cs.onSurface.withOpacity(0.04),
          border: Border.all(
            color: selected ? cs.primary.withOpacity(0.70) : cs.onSurface.withOpacity(0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: selected ? cs.primary.withOpacity(0.18) : cs.onSurface.withOpacity(0.06),
                border: Border.all(
                  color: selected ? cs.primary.withOpacity(0.70) : cs.onSurface.withOpacity(0.12),
                ),
              ),
              child: Icon(icon, color: selected ? cs.primary : cs.onSurface.withOpacity(0.72)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.70),
                      height: 1.25,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: selected ? cs.primary : cs.onSurface.withOpacity(0.06),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                selected ? l10n.tr('common_selected') : l10n.tr('common_select'),
                style: TextStyle(
                  color: selected ? cs.onPrimary : cs.onSurface.withOpacity(0.72),
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
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_details_title'), Icons.edit_note),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: l10n.tr('league_create_league_name_required_label'),
            prefixIcon: const Icon(Icons.edit_note),
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
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            labelText: l10n.tr('league_create_league_description_recommended_label'),
            alignLabelWithHint: true,
            prefixIcon: const Icon(Icons.subject),
          ),
        ),
        const SizedBox(height: 12),
        _infoBanner(
          icon: _typeIcon,
          title: '$_typeLabel • ${l10n.tr('league_create_info_type_max_teams_prefix')} $_maxTeams',
          subtitle: '${l10n.tr('league_create_info_format_prefix')} ${_format.displayName}',
        ),
      ],
    );
  }

  Widget _stepPrivacy(BuildContext context, {Key? key}) {
    final l10n = context.l10n;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_privacy_title'), Icons.lock),
        const SizedBox(height: 10),
        _privacyTile(
          value: LeaguePrivacy.public,
          title: l10n.tr('league_create_public_title'),
          subtitle: l10n.tr('league_create_public_subtitle'),
        ),
        const SizedBox(height: 10),
        _privacyTile(
          value: LeaguePrivacy.private,
          title: l10n.tr('league_create_private_title'),
          subtitle: l10n.tr('league_create_private_subtitle'),
        ),
      ],
    );
  }

  Widget _privacyTile({
    required LeaguePrivacy value,
    required String title,
    required String subtitle,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final selected = _privacy == value;

    return InkWell(
      onTap: () => setState(() => _privacy = value),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected ? cs.primary.withOpacity(0.14) : cs.onSurface.withOpacity(0.04),
          border: Border.all(color: selected ? cs.primary.withOpacity(0.70) : cs.onSurface.withOpacity(0.12)),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? cs.primary : cs.onSurface.withOpacity(0.55),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.65),
                      height: 1.25,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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

  Widget _stepPayment(BuildContext context, {Key? key}) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    if (!_creationRequiresPayment) {
      return Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(l10n.tr('league_create_payment_title'), Icons.payments_outlined),
          const SizedBox(height: 10),
          _infoBanner(
            icon: Icons.verified,
            title: l10n.tr('league_create_no_payment_required_title'),
            subtitle: l10n.tr('league_create_no_payment_required_subtitle'),
            accent: cs.primary,
          ),
        ],
      );
    }

    final statusTitle =
        _paymentCompleted ? l10n.tr('league_create_payment_completed_title') : l10n.tr('league_create_payment_required_title');
    final statusSubtitle = _paymentCompleted
        ? '${l10n.tr('league_create_receipt_prefix')} ${_payment?.receiptId ?? ''}'
        : l10n.tr('league_create_payment_required_subtitle');

    final statusIcon = _paymentCompleted ? Icons.verified : Icons.lock_outline;
    final accent = _paymentCompleted ? cs.primary : _premiumAmber;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_payment_title'), Icons.payments_outlined),
        const SizedBox(height: 10),
        _infoBanner(icon: statusIcon, title: statusTitle, subtitle: statusSubtitle, accent: accent),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _submitting
              ? null
              : () async {
                  final name = _name.text.trim().isEmpty ? l10n.tr('common_league_placeholder') : _name.text.trim();
                  final result = await context.push<LeagueCreationPaymentResult?>(
                    '/leagues/create/payment',
                    extra: {'leagueName': name},
                  );
                  if (!mounted) return;

                  if (result != null && result.success) {
                    setState(() => _payment = result);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.tr('league_create_payment_successful')),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  if (result == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.tr('league_create_payment_cancelled')),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(result.errorMessage ?? l10n.tr('leagues_payment_failed')),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: Text(
            _paymentCompleted ? l10n.tr('league_create_payment_done_view_receipt') : l10n.tr('league_create_pay_now'),
          ),
        ),
      ],
    );
  }

  Widget _stepConfirm(BuildContext context, {Key? key}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final canCreate = _type != null && _name.text.trim().isNotEmpty && (!_creationRequiresPayment || _paymentCompleted);

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_confirm_title'), Icons.check_circle_outline),
        const SizedBox(height: 10),
        _infoBanner(
          icon: _typeIcon,
          title: _typeLabel,
          subtitle: _name.text.trim().isEmpty ? l10n.tr('league_create_league_name_not_set') : _name.text.trim(),
        ),
        const SizedBox(height: 10),
        _confirmRow(
          Icons.lock,
          l10n.tr('league_create_confirm_privacy_label'),
          _privacy == LeaguePrivacy.private ? l10n.tr('league_create_private') : l10n.tr('league_create_public'),
        ),
        _confirmRow(Icons.groups, l10n.tr('league_create_confirm_max_teams_label'), '$_maxTeams'),
        _confirmRow(
          _creationRequiresPayment ? (_paymentCompleted ? Icons.verified : Icons.lock_outline) : Icons.verified,
          l10n.tr('league_create_confirm_creation_fee_label'),
          _creationRequiresPayment
              ? (_paymentCompleted ? l10n.tr('league_create_fee_paid') : l10n.tr('league_create_fee_required'))
              : l10n.tr('league_create_fee_free'),
          valueColor: _creationRequiresPayment
              ? (_paymentCompleted ? cs.primary : _premiumAmber)
              : cs.primary,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: cs.onSurface.withOpacity(0.04),
            border: Border.all(color: cs.onSurface.withOpacity(0.10)),
          ),
          child: SwitchListTile.adaptive(
            value: _creatorWillParticipate,
            onChanged: _submitting ? null : (v) => setState(() => _creatorWillParticipate = v),
            activeColor: cs.primary,
            contentPadding: EdgeInsets.zero,
            title: Text(
              l10n.tr('league_create_creator_participate_title'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              l10n.tr('league_create_creator_participate_subtitle'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.65),
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          l10n.tr('league_create_admin_notice'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurface.withOpacity(0.70),
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: (_submitting || !canCreate) ? null : () => _create(context),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: _submitting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(l10n.tr('league_create_create_league_button_upper'), style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
      ],
    );
  }

  Widget _confirmRow(IconData icon, String label, String value, {Color? valueColor}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withOpacity(0.70),
              fontWeight: FontWeight.w900,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                color: valueColor ?? cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text, IconData icon) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: cs.primary.withOpacity(0.14),
            border: Border.all(color: cs.primary.withOpacity(0.35)),
          ),
          child: Icon(icon, size: 18, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Text(
          text,
          style: theme.textTheme.titleMedium?.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final a = accent ?? cs.primary;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.onSurface.withOpacity(0.04),
        border: Border.all(color: a.withOpacity(0.35)),
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
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.70),
                    height: 1.25,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
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
    final cs = Theme.of(context).colorScheme;

    final isLast = _step == 4;
    final canGoBack = !_submitting;
    final canGoNext = !_submitting;

    final nextLabel = isLast ? l10n.tr('common_done') : l10n.tr('common_next');
    final backLabel = _step == 0 ? l10n.tr('common_cancel') : l10n.tr('common_back');

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
              side: BorderSide(color: cs.onSurface.withOpacity(0.18)),
              foregroundColor: cs.onSurface.withOpacity(0.80),
            ),
            child: Text(backLabel.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: !canGoNext
                ? null
                : () async {
                    if (isLast) {
                      if (_createdLeague == null) context.pop();
                      return;
                    }
                    final ok = await _validateAndAdvance(context);
                    if (ok) setState(() => _step++);
                  },
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(nextLabel.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }

  Future<bool> _validateAndAdvance(BuildContext context) async {
    final l10n = context.l10n;

    if (_step == 0) {
      if (_type == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('league_create_error_select_type')), behavior: SnackBarBehavior.floating),
        );
        return false;
      }
      return true;
    }

    if (_step == 1) {
      if (_name.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('league_create_error_name_required')), behavior: SnackBarBehavior.floating),
        );
        return false;
      }
      return true;
    }

    if (_step == 3) {
      if (_creationRequiresPayment && !_paymentCompleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tr('league_create_error_complete_payment_to_continue')), behavior: SnackBarBehavior.floating),
        );
        return false;
      }
      return true;
    }

    return true;
  }

  Future<void> _create(BuildContext context) async {
    final l10n = context.l10n;

    if (_type == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_create_error_select_type')), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_create_error_name_required')), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (_creationRequiresPayment && !_paymentCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_create_error_payment_must_be_completed')), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    if (!_allowedMaxTeams.contains(_maxTeams)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tr('league_create_error_invalid_team_count')), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final prefs = ref.read(prefsServiceProvider);
      final repo = LocalLeaguesRepository(prefs);

      final organizerUserId = await CurrentUser.getUserId();

      String? creatorTeamName;
      if (_creatorWillParticipate) {
        final profile = await UserProfileRepository().fetchByUserId(organizerUserId);
        final name = profile?.teamName.trim() ?? '';
        if (name.isEmpty) {
          throw StateError(l10n.tr('league_create_error_profile_team_name_missing'));
        }
        creatorTeamName = name;
      }

      final leagueId = _uuid.v4();
      final now = DateTime.now().millisecondsSinceEpoch;

      final settings = LeagueSettings.defaultsFor(_format).copyWith(lastPulledAtMs: 0);

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

      if (_creatorWillParticipate && creatorTeamName != null) {
        final existingTeams = await repo.getTeams(stored.id);

        final alreadyHasTeam = existingTeams.any((t) => t.id == organizerUserId);
        if (!alreadyHasTeam) {
          final String? groupId =
              stored.format == LeagueFormat.uclGroup ? _pickRandomGroupNameForMaxTeams(stored.maxTeams) : null;

          final team = Team(
            id: organizerUserId,
            leagueId: stored.id,
            name: creatorTeamName,
            groupId: groupId,
            updatedAtMs: DateTime.now().millisecondsSinceEpoch,
            version: 1,
          );

          await repo.saveTeams(stored.id, <Team>[...existingTeams, team]);
        }

        await repo.assignTeamToUserInLeague(
          leagueId: stored.id,
          userId: organizerUserId,
          teamId: organizerUserId,
        );
      }

      if (!mounted) return;
      setState(() {
        _createdLeague = stored;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('league_create_error_failed_to_create_prefix')}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _StepMeta {
  final String title;
  final IconData icon;

  const _StepMeta(this.title, this.icon);
}
