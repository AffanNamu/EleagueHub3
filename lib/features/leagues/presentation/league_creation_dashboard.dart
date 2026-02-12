import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/user_friendly_error.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/league_flip_card.dart';
import '../../auth/data/user_profile_repository.dart';
import '../../auth/models/user_profile.dart';
import '../data/leagues_repository_local.dart';
import '../logic/coupon_config_service.dart';
import '../logic/league_creation_payment_service.dart';
import '../logic/league_media_service.dart';
import '../models/enums.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';

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

  late final String _draftLeagueId;

  int _step = 0;

  LeagueCreationType? _type;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();

  // OPTIONAL images (URLs or data:image;base64,...)
  final TextEditingController _leagueImageUrl = TextEditingController();
  final TextEditingController _sponsorImageUrl = TextEditingController();

  bool _uploadingLeagueImage = false;
  bool _uploadingSponsorImage = false;

  LeaguePrivacy _privacy = LeaguePrivacy.private;

  LeagueCreationPaymentResult? _payment;

  bool _submitting = false;
  League? _createdLeague;

  int? _selectedMaxTeams;

  bool _creatorWillParticipate = false;

  static const Color _premiumAmber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    // Stable ID so any uploaded media is associated with the league we end up creating.
    _draftLeagueId = _uuid.v4();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _leagueImageUrl.dispose();
    _sponsorImageUrl.dispose();
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

  // Coupons (optional add-on):
  // IMPORTANT: couponDiscountPercent is now DISCOUNT percent (0..100),
  // not "users pay percent".
  bool get _couponsEnabled => (_payment?.buyCouponsForParticipants ?? false) && _paymentCompleted;
  int get _couponCount => _couponsEnabled ? (_payment?.couponCount ?? 0) : 0;
  int get _discountPercent => _couponsEnabled ? (_payment?.couponDiscountPercent ?? 0) : 0;

  String get _couponLabel {
    if (!_couponsEnabled) return 'Coupons: None';
    final pctLabel = 'Discount $_discountPercent%';
    final countLabel = _couponCount > 0 ? ' • Qty: $_couponCount' : '';
    return 'Coupons: $pctLabel$countLabel';
  }

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

  Future<void> _uploadImage({
    required LeagueMediaKind kind,
  }) async {
    final l10n = context.l10n;
    if (_submitting) return;

    if (kind == LeagueMediaKind.leagueImage) {
      if (_uploadingLeagueImage) return;
      setState(() => _uploadingLeagueImage = true);
    } else {
      if (_uploadingSponsorImage) return;
      setState(() => _uploadingSponsorImage = true);
    }

    try {
      final service = LeagueMediaService();
      final url = await service
          .pickAndUploadImage(
            leagueId: _draftLeagueId,
            kind: kind,
          )
          .timeout(const Duration(seconds: 40));

      if (!mounted) return;

      if (url == null || url.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image not selected or upload failed.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      setState(() {
        if (kind == LeagueMediaKind.leagueImage) {
          _leagueImageUrl.text = url;
        } else {
          _sponsorImageUrl.text = url;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('common_done')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'))),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _uploadingLeagueImage = false;
        _uploadingSponsorImage = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 900;

    // REQUIRED: League creation must be tied to Firebase Auth UID so Firestore rules
    // can authorize organizer-only actions (coupon config / coupon codes).
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.trim().isEmpty) {
      return GlassScaffold(
        appBar: AppBar(
          title: Text(l10n.tr('league_create_appbar_title')),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Glass(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.login, color: cs.primary, size: 44),
                      const SizedBox(height: 10),
                      Text(
                        'Sign in required',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please sign in to create a league.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withOpacity(0.70),
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () => context.pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

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
                          if (_couponsEnabled) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Coupons are configured for this league. If you don’t see them yet, please try again in a moment.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurface.withOpacity(0.65),
                                height: 1.35,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
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

    final paymentColor = _creationRequiresPayment ? (_paymentCompleted ? cs.primary : _premiumAmber) : cs.primary;

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
          if (_couponsEnabled) ...[
            _summaryRow(
              Icons.confirmation_number_outlined,
              'Coupons',
              _couponLabel.replaceFirst('Coupons: ', ''),
              valueColor: cs.primary,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _creationRequiresPayment ? l10n.tr('league_create_fee_note_requires_payment') : l10n.tr('league_create_fee_note_free'),
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
    final cs = Theme.of(context).colorScheme;

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

  // ---- UI step widgets unchanged from your original (below) ----

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
        _sectionTitle('Images (optional)', Icons.image_outlined),
        const SizedBox(height: 10),
        _OptionalImageField(
          controller: _leagueImageUrl,
          label: 'League Image URL (optional)',
          uploading: _uploadingLeagueImage,
          onUpload: () => _uploadImage(kind: LeagueMediaKind.leagueImage),
          onClear: () => setState(() => _leagueImageUrl.text = ''),
        ),
        const SizedBox(height: 10),
        _OptionalImageField(
          controller: _sponsorImageUrl,
          label: 'Sponsor Image URL (optional)',
          uploading: _uploadingSponsorImage,
          onUpload: () => _uploadImage(kind: LeagueMediaKind.sponsorImage),
          onClear: () => setState(() => _sponsorImageUrl.text = ''),
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

    final statusTitle = _paymentCompleted
        ? l10n.tr('league_create_payment_completed_title')
        : l10n.tr('league_create_payment_required_title');
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
                    extra: <String, dynamic>{
                      'leagueId': _draftLeagueId,
                      'leagueName': name,
                      'addonsOnly': false,
                      'existingCouponsEnabled': _couponsEnabled,
                      'existingCouponCount': _couponCount,
                      'existingCouponDiscountPercent': _discountPercent, // discount %
                    },
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
        if (_couponsEnabled)
          _confirmRow(
            Icons.confirmation_number_outlined,
            'Coupons',
            _couponLabel.replaceFirst('Coupons: ', ''),
            valueColor: cs.primary,
          ),
        _confirmRow(
          _creationRequiresPayment ? (_paymentCompleted ? Icons.verified : Icons.lock_outline) : Icons.verified,
          l10n.tr('league_create_confirm_creation_fee_label'),
          _creationRequiresPayment
              ? (_paymentCompleted ? l10n.tr('league_create_fee_paid') : l10n.tr('league_create_fee_required'))
              : l10n.tr('league_create_fee_free'),
          valueColor: _creationRequiresPayment ? (_paymentCompleted ? cs.primary : _premiumAmber) : cs.primary,
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
      final organizerAuthUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (organizerAuthUid.isEmpty) {
        throw StateError('unauthenticated');
      }

      // UI-only identity (short share id). Rules never use this.
      final derivedShareId = UserProfile.deriveShareIdFromUid(organizerAuthUid).trim();
      final organizerUserId = derivedShareId.isNotEmpty ? derivedShareId : organizerAuthUid;

      if (_creatorWillParticipate) {
        // Profiles are stored by Firebase UID.
        final profile = await UserProfileRepository()
            .fetchByUserId(organizerAuthUid)
            .timeout(const Duration(seconds: 12));
        final name = profile?.teamName.trim() ?? '';
        if (name.isEmpty) {
          throw StateError(l10n.tr('league_create_error_profile_team_name_missing'));
        }
      }

      final leagueId = _draftLeagueId;
      final now = DateTime.now().millisecondsSinceEpoch;

      final settings = LeagueSettings.defaultsFor(_format).copyWith(lastPulledAtMs: 0);

      final couponsEnabled = _couponsEnabled;
      final discountPercent = _discountPercent.clamp(0, 100);
      final couponCount = _couponCount < 0 ? 0 : _couponCount;

      final league = League(
        id: leagueId,
        name: _name.text.trim(),
        description: _description.text.trim(),

        // optional images
        leagueImageUrl: _leagueImageUrl.text.trim(),
        sponsorImageUrl: _sponsorImageUrl.text.trim(),

        viewerCapacity: 0,

        // coupons (optional add-on)
        couponsEnabled: couponsEnabled,
        couponDiscountPercent: discountPercent,
        couponCount: couponCount,

        format: _format,
        privacy: _privacy,
        region: 'Global',
        maxTeams: _maxTeams,
        season: '2026',

        organizerUid: organizerAuthUid, // Firebase UID authority (rules)
        organizerUserId: organizerUserId, // short/shareId for UI

        code: '',
        qrPayloadOverride: '',
        settings: settings,
        updatedAtMs: now,
        version: 1,
      );

      final repo = LocalLeaguesRepository(ref.read(prefsServiceProvider));
      final stored = await repo
          .createLeagueLocally(
            league: league,
            organizerUserId: organizerUserId,
          )
          .timeout(const Duration(seconds: 25));

      // Coupons: league doc is already written. Create/update coupon config online.
      if (couponsEnabled && couponCount > 0) {
        try {
          final plan = await RemotePricingService.instance
              .getPlanForLocale(Localizations.maybeLocaleOf(context))
              .timeout(const Duration(seconds: 15));

          await CouponConfigService()
              .createOrIncrementOnPurchase(
                leagueId: leagueId,
                organizerUserId: organizerAuthUid,
                qtyPurchased: couponCount,
                discountPercent: discountPercent,
                plan: plan,
              )
              .timeout(const Duration(seconds: 20));
        } catch (_) {
          // Do not expose technical errors. Keep the league created successfully.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("We saved your league, but couldn't update coupons right now. Please try again."),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _createdLeague = stored;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);

      final msg = UserFriendlyError.toMessage(e is Object ? e : Exception('unknown'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.tr('league_create_error_failed_to_create_prefix')}: $msg'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

class _OptionalImageField extends StatelessWidget {
  const _OptionalImageField({
    required this.controller,
    required this.label,
    required this.uploading,
    required this.onUpload,
    required this.onClear,
  });

  final TextEditingController controller;
  final String label;
  final bool uploading;
  final VoidCallback onUpload;
  final VoidCallback onClear;

  Uint8List? _tryDecodeDataUri(String raw) {
    final s = raw.trim();
    if (!s.startsWith('data:image')) return null;
    final idx = s.indexOf('base64,');
    if (idx < 0) return null;
    final b64 = s.substring(idx + 'base64,'.length);
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final url = controller.text.trim();
    final bytes = url.isEmpty ? null : _tryDecodeDataUri(url);

    final preview = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.onSurface.withOpacity(0.14)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
            : (url.isNotEmpty
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.emoji_events_outlined, color: cs.onSurface.withOpacity(0.55)),
                  )
                : Icon(Icons.emoji_events_outlined, color: cs.onSurface.withOpacity(0.55))),
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        preview,
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.link),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: uploading
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                    )
                  : IconButton(
                      tooltip: 'Upload',
                      onPressed: onUpload,
                      icon: const Icon(Icons.cloud_upload_outlined),
                    ),
            ),
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                tooltip: 'Clear',
                onPressed: onClear,
                icon: const Icon(Icons.clear),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepMeta {
  final String title;
  final IconData icon;

  const _StepMeta(this.title, this.icon);
}
