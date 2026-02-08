import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/persistence/prefs_service.dart';
import '../../../core/services/sync_trigger.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../../../widgets/league_flip_card.dart';
import '../data/leagues_repository_local.dart';
import '../logic/league_creation_payment_service.dart';
import '../logic/league_media_service.dart';
import '../models/enums.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import '../utils/current_user.dart';

class LeagueCreateWizard extends ConsumerStatefulWidget {
  const LeagueCreateWizard({super.key});

  @override
  ConsumerState<LeagueCreateWizard> createState() => _LeagueCreateWizardState();
}

class _LeagueCreateWizardState extends ConsumerState<LeagueCreateWizard> {
  final _uuid = const Uuid();
  late final String _draftLeagueId;

  int _step = 0;

  final _name = TextEditingController();
  final _description = TextEditingController();

  // OPTIONAL images (URLs or data:image/...;base64,...)
  final _leagueImageUrl = TextEditingController();
  final _sponsorImageUrl = TextEditingController();

  bool _uploadingLeagueImage = false;
  bool _uploadingSponsorImage = false;

  LeagueFormat _format = LeagueFormat.classic;
  LeaguePrivacy _privacy = LeaguePrivacy.private;

  bool _doubleRoundRobin = true;
  bool _submitting = false;

  LeagueCreationPaymentResult? _payment;

  League? _createdLeague;

  static const Color _premiumAmber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _draftLeagueId = _uuid.v4();
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

  bool get _creationRequiresPayment {
    return _format == LeagueFormat.uclGroup || _format == LeagueFormat.uclSwiss;
  }

  bool get _paymentCompleted => _payment?.success == true;

  bool get _couponsEnabled => (_payment?.buyCouponsForParticipants ?? false) && _paymentCompleted;

  int get _couponPercent => _couponsEnabled ? (_payment?.couponDiscountPercent ?? 0) : 0;

  int get _couponCount => _couponsEnabled ? (_payment?.couponCount ?? 0) : 0;

  String get _couponLabel {
    if (!_couponsEnabled) return 'Coupons: None';

    final pctLabel = _couponPercent >= 100 ? 'Free access (100%)' : '$_couponPercent% discount';
    final countLabel = _couponCount > 0 ? ' • Qty: $_couponCount' : '';
    return 'Coupons: $pctLabel$countLabel';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _leagueImageUrl.dispose();
    _sponsorImageUrl.dispose();
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

  Future<void> _uploadImage({
    required LeagueMediaKind kind,
  }) async {
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
      final url = await service.pickAndUploadImage(
        leagueId: _draftLeagueId,
        kind: kind,
      );

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
          content: Text(context.l10n.tr('common_done')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
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
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: cs.onSurface.withOpacity(0.75),
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (league.hasCoupons) ...[
                            const SizedBox(height: 10),
                            Text(
                              'Coupons were enabled for this league. If you don’t see them yet, tap Sync in Admin or reopen Profile → Coupons after sync completes.',
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
            valueColor: paymentColor,
          ),
          if ((_payment?.viewerCapacity ?? 0) > 0) ...[
            _summaryRow(
              Icons.visibility,
              'Viewers',
              '${_payment!.viewerCapacity}',
              valueColor: cs.primary,
            ),
          ],
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
            _unlockNote(l10n),
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
      padding: const EdgeInsets.only(bottom: 10),
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

  Widget _buildStepHeader() {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_wizard_step_basics'), Icons.edit_note),
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

        // Images (optional)
        const SizedBox(height: 14),
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
        DropdownButtonFormField<LeagueFormat>(
          value: _format,
          dropdownColor: cs.surface,
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: l10n.tr('league_create_wizard_tournament_format_label'),
            prefixIcon: const Icon(Icons.format_list_bulleted),
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
          dropdownColor: cs.surface,
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            labelText: l10n.tr('league_create_privacy_title'),
            prefixIcon: const Icon(Icons.lock),
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
          accent: cs.primary,
        ),
      ],
    );
  }

  Widget _rulesStep({Key? key}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
            color: cs.onSurface.withOpacity(0.04),
            border: Border.all(color: cs.onSurface.withOpacity(0.10)),
          ),
          child: SwitchListTile.adaptive(
            value: _doubleRoundRobin,
            onChanged: (v) => setState(() => _doubleRoundRobin = v),
            activeColor: cs.primary,
            title: Text(
              l10n.tr('league_create_wizard_double_round_robin_title'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              l10n.tr('league_create_wizard_double_round_robin_subtitle'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withOpacity(0.60),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 12),
        _infoBanner(
          icon: _creationRequiresPayment ? Icons.lock_outline : Icons.verified,
          title: _creationRequiresPayment
              ? l10n.tr('league_create_payment_required_title')
              : l10n.tr('league_create_no_payment_required_title'),
          subtitle: _creationRequiresPayment
              ? l10n.tr('league_create_payment_required_subtitle')
              : l10n.tr('league_create_no_payment_required_subtitle'),
          accent: _creationRequiresPayment ? _premiumAmber : cs.primary,
        ),
      ],
    );
  }

  Widget _reviewStep({Key? key}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final canPay = _creationRequiresPayment && _name.text.trim().isNotEmpty;
    final canCreate = _name.text.trim().isNotEmpty && (!_creationRequiresPayment || _paymentCompleted);

    final paymentAccent = !_creationRequiresPayment ? cs.primary : (_paymentCompleted ? cs.primary : _premiumAmber);

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(l10n.tr('league_create_wizard_step_review'), Icons.check_circle_outline),
        const SizedBox(height: 10),
        _reviewRow(
          Icons.label,
          l10n.tr('league_create_summary_name_label'),
          _name.text.trim().isEmpty ? l10n.tr('league_create_summary_not_set') : _name.text.trim(),
        ),
        _reviewRow(
          Icons.subject,
          l10n.tr('league_create_wizard_description_label'),
          _description.text.trim().isEmpty ? l10n.tr('common_none') : _description.text.trim(),
        ),
        _reviewRow(
          Icons.image_outlined,
          'League Image',
          _leagueImageUrl.text.trim().isEmpty ? l10n.tr('common_none') : l10n.tr('common_yes'),
        ),
        _reviewRow(
          Icons.handshake_outlined,
          'Sponsor Image',
          _sponsorImageUrl.text.trim().isEmpty ? l10n.tr('common_none') : l10n.tr('common_yes'),
        ),
        if ((_payment?.viewerCapacity ?? 0) > 0)
          _reviewRow(
            Icons.visibility,
            'Viewers',
            '${_payment!.viewerCapacity}',
          ),
        if (_couponsEnabled)
          _reviewRow(
            Icons.confirmation_number_outlined,
            'Coupons',
            _couponLabel.replaceFirst('Coupons: ', ''),
          ),
        _reviewRow(Icons.format_list_bulleted, l10n.tr('league_create_summary_type_label'), _formatLabel(l10n)),
        _reviewRow(Icons.lock, l10n.tr('league_create_summary_privacy_label'), _privacyLabel(l10n)),
        _reviewRow(Icons.groups, l10n.tr('league_create_summary_max_teams_label'), '$_maxTeams'),
        _reviewRow(
          Icons.repeat,
          l10n.tr('league_create_wizard_double_rr_label'),
          _doubleRoundRobin ? l10n.tr('common_yes') : l10n.tr('common_no'),
        ),
        const SizedBox(height: 10),
        _infoBanner(
          icon: !_creationRequiresPayment ? Icons.verified : (_paymentCompleted ? Icons.verified : Icons.lock_outline),
          title: !_creationRequiresPayment
              ? '${l10n.tr('league_create_summary_creation_fee_label')}: ${l10n.tr('league_create_fee_free')}'
              : (_paymentCompleted
                  ? '${l10n.tr('league_create_summary_creation_fee_label')}: ${l10n.tr('league_create_fee_paid')}'
                  : '${l10n.tr('league_create_summary_creation_fee_label')}: ${l10n.tr('league_create_fee_required')}'),
          subtitle: !_creationRequiresPayment
              ? l10n.tr('league_create_fee_note_free')
              : (_paymentCompleted
                  ? '${l10n.tr('league_create_receipt_prefix')} ${_payment?.receiptId ?? ''}'
                  : l10n.tr('league_create_error_complete_payment_to_continue')),
          accent: paymentAccent,
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
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              _paymentCompleted ? l10n.tr('league_create_payment_done_view_receipt') : l10n.tr('league_create_pay_now'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: (_submitting || !canCreate) ? null : () => _create(context),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
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
        const SizedBox(height: 8),
        Text(
          l10n.tr('league_create_fee_note_free'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withOpacity(0.55),
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _reviewRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
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
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
                height: 1.25,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

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
              side: BorderSide(color: cs.onSurface.withOpacity(0.18)),
              foregroundColor: cs.onSurface.withOpacity(0.80),
            ),
            child: Text(
              _step == 0 ? l10n.tr('common_cancel') : l10n.tr('common_back'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
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
                        SnackBar(
                          content: Text(l10n.tr('league_create_error_name_required')),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                      return;
                    }

                    setState(() => _step++);
                  },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text(
              isLast ? l10n.tr('common_done') : l10n.tr('common_next'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final l10n = context.l10n;

    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_create_error_name_required')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_creationRequiresPayment && !_paymentCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tr('league_create_error_payment_must_be_completed')),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    final prefs = ref.read(prefsServiceProvider);
    final repo = LocalLeaguesRepository(prefs);

    final organizerUserId = await CurrentUser.getOrCreateUserId();

    final leagueId = _draftLeagueId;
    final now = DateTime.now().millisecondsSinceEpoch;

    final settings = LeagueSettings.defaultsFor(_format).copyWith(
      doubleRoundRobin: _doubleRoundRobin,
      lastPulledAtMs: 0,
    );

    final couponsEnabled = _paymentCompleted && (_payment?.buyCouponsForParticipants ?? false);
    final couponPercent = couponsEnabled ? (_payment?.couponDiscountPercent ?? 0) : 0;
    final couponCount = couponsEnabled ? (_payment?.couponCount ?? 0) : 0;

    final league = League(
      id: leagueId,
      name: _name.text.trim(),
      description: _description.text.trim(),

      // optional images
      leagueImageUrl: _leagueImageUrl.text.trim(),
      sponsorImageUrl: _sponsorImageUrl.text.trim(),

      // optional paid add-on
      viewerCapacity: _payment?.viewerCapacity ?? 0,

      // optional paid add-on
      couponsEnabled: couponsEnabled,
      couponDiscountPercent: couponPercent,
      couponCount: couponCount,

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

    // Best-effort: immediately sync so coupons can be generated in the cloud,
    // otherwise Profile/Admin coupon lists will be empty until the organizer taps Sync.
    //
    // Never blocks league creation; failures are non-fatal (offline-first).
    // ignore: discarded_futures
    SyncTrigger.trySync();

    if (!mounted) return;
    setState(() {
      _createdLeague = stored;
      _submitting = false;
    });

    if (couponsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync started: coupons will appear in Admin/Profile after sync completes.'),
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
                    errorBuilder: (_, __, ___) => Icon(Icons.emoji_events_outlined, color: cs.onSurface.withOpacity(0.55)),
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
