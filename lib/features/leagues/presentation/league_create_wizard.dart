import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
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
import '../../auth/models/user_profile.dart';
import '../data/leagues_repository_firebase.dart';
import '../logic/coupon_config_service.dart';
import '../logic/league_creation_payment_service.dart';
import '../logic/league_media_service.dart';
import '../models/enums.dart';
import '../models/league.dart';
import '../models/league_format.dart';
import '../models/league_settings.dart';
import 'screens/edit_league_rewards_screen.dart';

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

  // Existing flag used by settings/fixture generation
  bool _doubleRoundRobin = false;

  // NEW: Saved at league doc root as `homeAwayEnabled` (default false)
  bool _homeAwayEnabled = false;

  // NEW: Rewards toggle (wizard-level intent)
  bool _containsRewards = false;

  bool _submitting = false;

  LeagueCreationPaymentResult? _payment;

  League? _createdLeague;

  static const Color _premiumAmber = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _draftLeagueId = _uuid.v4();
  }

  bool get _supportsHomeAwayMatches => _format == LeagueFormat.classic || _format == LeagueFormat.uclGroup;

  int get _maxTeams {
    switch (_format) {
      case LeagueFormat.classic:
        return 20;
      case LeagueFormat.uclGroup:
        return 32;
      case LeagueFormat.uclSwiss:
        return 36;
    }
  }

  bool get _creationRequiresPayment {
    return _format == LeagueFormat.uclGroup || _format == LeagueFormat.uclSwiss;
  }

  bool get _paymentCompleted => _payment?.success == true;

  bool get _couponsEnabled => (_payment?.buyCouponsForParticipants ?? false) && _paymentCompleted;

  int get _discountPercent => _couponsEnabled ? (_payment?.couponDiscountPercent ?? 0) : 0;

  int get _couponCount => _couponsEnabled ? (_payment?.couponCount ?? 0) : 0;

  String get _couponLabel {
    if (!_couponsEnabled) return 'Coupons: None';
    final pctLabel = 'Discount $_discountPercent%';
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

  void _showSnack(String message) {
    if (!mounted) return;
    final msg = message.trim();
    if (msg.isEmpty) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
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
      final url = await service
          .pickAndUploadImage(
            leagueId: _draftLeagueId,
            kind: kind,
          )
          .timeout(const Duration(seconds: 40));

      if (!mounted) return;

      if (url == null || url.trim().isEmpty) {
        _showSnack('Image not selected or upload failed. Please try again.');
        return;
      }

      setState(() {
        if (kind == LeagueMediaKind.leagueImage) {
          _leagueImageUrl.text = url;
        } else {
          _sponsorImageUrl.text = url;
        }
      });

      _showSnack(context.l10n.tr('common_done'));
    } catch (e) {
      _showSnack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    } finally {
      if (!mounted) return;
      setState(() {
        _uploadingLeagueImage = false;
        _uploadingSponsorImage = false;
      });
    }
  }

  String _generateJoinCode({int length = 6}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<String> _generateUniqueJoinCode() async {
    final firestore = FirebaseFirestore.instance;

    for (int i = 0; i < 6; i++) {
      final code = _generateJoinCode();
      final snap = await firestore
          .collection('leagues')
          .where('code', isEqualTo: code)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (snap.docs.isEmpty) return code;
    }

    throw StateError("We couldn't create a league code right now. Please try again.");
  }

  Future<void> _payIfNeeded() async {
    final l10n = context.l10n;
    if (_submitting) return;

    if (!_creationRequiresPayment) return;

    final name = _name.text.trim().isEmpty ? l10n.tr('common_league_placeholder') : _name.text.trim();

    final result = await context.push<LeagueCreationPaymentResult?>(
      '/leagues/create/payment',
      extra: <String, dynamic>{
        'leagueId': _draftLeagueId,
        'leagueName': name,
        'addonsOnly': false,
        'existingCouponsEnabled': _couponsEnabled,
        'existingCouponCount': _couponCount,
        'existingCouponDiscountPercent': _discountPercent,
      },
    );

    if (!mounted) return;

    if (result != null && result.success) {
      setState(() => _payment = result);
      _showSnack(l10n.tr('league_create_payment_successful'));
      return;
    }

    if (result == null) {
      _showSnack(l10n.tr('league_create_payment_cancelled'));
      return;
    }

    _showSnack(result.errorMessage ?? l10n.tr('leagues_payment_failed'));
  }

  Future<bool> _validateAndNext() async {
    final l10n = context.l10n;

    if (_step == 0) {
      if (_name.text.trim().isEmpty) {
        _showSnack(l10n.tr('league_create_error_name_required'));
        return false;
      }
      setState(() => _step = 1);
      return true;
    }

    if (_step == 1) {
      setState(() => _step = 2);
      return true;
    }

    return true;
  }

  void _backOrClose() {
    if (_submitting) return;
    if (_step == 0) {
      context.pop();
      return;
    }
    setState(() => _step = max(0, _step - 1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final authUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
    if (authUid.isEmpty) {
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
                      leagueId: league.id,
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
                              'Coupons are configured for this league. If you don't see them yet, try again in a moment.',
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
                          if (_containsRewards) ...[
                            const SizedBox(height: 10),
                            FilledButton.tonalIcon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => EditLeagueRewardsScreen(leagueId: league.id),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.card_giftcard_outlined),
                              label: const Text(
                                'Manage Rewards',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                          ],
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

    final paymentColor = _creationRequiresPayment ? (_paymentCompleted ? cs.primary : _premiumAmber) : cs.primary;

    Widget row(IconData icon, String label, String value, {Color? color}) {
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
                  color: color ?? cs.onSurface,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      );
    }

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
          row(Icons.auto_awesome, l10n.tr('league_create_summary_type_label'), _format.displayName),
          row(
            Icons.label,
            l10n.tr('league_create_summary_name_label'),
            _name.text.trim().isEmpty ? l10n.tr('league_create_summary_not_set') : _name.text.trim(),
          ),
          row(
            Icons.lock,
            l10n.tr('league_create_summary_privacy_label'),
            _privacy == LeaguePrivacy.private ? l10n.tr('league_create_private') : l10n.tr('league_create_public'),
          ),
          row(Icons.groups, l10n.tr('league_create_summary_max_teams_label'), '$_maxTeams'),
          if (_supportsHomeAwayMatches)
            row(
              Icons.swap_horiz,
              'Home/Away',
              _homeAwayEnabled ? 'Enabled' : 'Disabled',
              color: _homeAwayEnabled ? cs.primary : cs.onSurface.withOpacity(0.75),
            ),
          row(
            Icons.card_giftcard_outlined,
            'Rewards',
            _containsRewards ? 'Yes' : 'No',
            color: _containsRewards ? cs.primary : cs.onSurface.withOpacity(0.75),
          ),
          row(
            _creationRequiresPayment ? (_paymentCompleted ? Icons.verified : Icons.lock_outline) : Icons.verified,
            l10n.tr('league_create_summary_creation_fee_label'),
            _creationRequiresPayment
                ? (_paymentCompleted ? l10n.tr('league_create_fee_paid') : l10n.tr('league_create_fee_required'))
                : l10n.tr('league_create_fee_free'),
            color: paymentColor,
          ),
          if (_couponsEnabled) ...[
            row(
              Icons.confirmation_number_outlined,
              'Coupons',
              _couponLabel.replaceFirst('Coupons: ', ''),
              color: cs.primary,
            ),
          ],
          const SizedBox(height: 10),
          Text(
            _unlockNote(context.l10n),
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

  String _unlockNote(AppLocalizations l10n) {
    return _creationRequiresPayment ? l10n.tr('league_create_fee_note_requires_payment') : l10n.tr('league_create_fee_note_free');
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
        return _stepBasics(key: key);
      case 1:
        return _stepRules(key: key);
      case 2:
        return _stepReview(key: key);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _stepBasics({Key? key}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget formatChip(LeagueFormat fmt, String label) {
      final selected = _format == fmt;
      return ChoiceChip(
        selected: selected,
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        selectedColor: cs.primary.withOpacity(0.18),
        backgroundColor: cs.onSurface.withOpacity(0.06),
        labelStyle: TextStyle(
          color: selected ? cs.primary : cs.onSurface.withOpacity(0.72),
          fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
        ),
        onSelected: _submitting
            ? null
            : (v) {
                if (!v) return;
                setState(() {
                  _format = fmt;
                  if (!_creationRequiresPayment) _payment = null;

                  // Home/Away is only applicable to classic + group.
                  if (!_supportsHomeAwayMatches) {
                    _homeAwayEnabled = false;
                    _doubleRoundRobin = false;
                  }
                });
              },
      );
    }

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Basics', Icons.edit_note),
        const SizedBox(height: 10),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'League name (required)',
            prefixIcon: Icon(Icons.edit_outlined),
          ),
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w700),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          minLines: 3,
          maxLines: 7,
          decoration: const InputDecoration(
            labelText: 'Description (optional)',
            prefixIcon: Icon(Icons.subject_outlined),
            alignLabelWithHint: true,
          ),
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _sectionTitle('Format', Icons.auto_awesome),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            formatChip(LeagueFormat.classic, 'Classic'),
            formatChip(LeagueFormat.uclGroup, 'Group'),
            formatChip(LeagueFormat.uclSwiss, 'Series'),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle('Images (optional)', Icons.image_outlined),
        const SizedBox(height: 10),
        _OptionalImageField(
          controller: _leagueImageUrl,
          label: 'League Image',
          uploading: _uploadingLeagueImage,
          onUpload: () => _uploadImage(kind: LeagueMediaKind.leagueImage),
          onClear: () => setState(() => _leagueImageUrl.text = ''),
        ),
        const SizedBox(height: 10),
        _OptionalImageField(
          controller: _sponsorImageUrl,
          label: 'Sponsor Image',
          uploading: _uploadingSponsorImage,
          onUpload: () => _uploadImage(kind: LeagueMediaKind.sponsorImage),
          onClear: () => setState(() => _sponsorImageUrl.text = ''),
        ),
      ],
    );
  }

  Widget _stepRules({Key? key}) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Rules & Access', Icons.rule),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: cs.onSurface.withOpacity(0.04),
            border: Border.all(color: cs.onSurface.withOpacity(0.10)),
          ),
          child: Column(
            children: [
              SwitchListTile.adaptive(
                value: _privacy == LeaguePrivacy.private,
                onChanged: _submitting
                    ? null
                    : (v) => setState(() => _privacy = v ? LeaguePrivacy.private : LeaguePrivacy.public),
                activeColor: cs.primary,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Private league',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  _privacy == LeaguePrivacy.private
                      ? 'Only members can view and join.'
                      : 'Anyone can view, join with code.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_supportsHomeAwayMatches) ...[
                Divider(color: cs.onSurface.withOpacity(0.12)),
                CheckboxListTile.adaptive(
                  value: _homeAwayEnabled,
                  onChanged: _submitting
                      ? null
                      : (v) {
                          final enabled = v ?? false;
                          setState(() {
                            _homeAwayEnabled = enabled;
                            // Keep existing flag in sync (used by LeagueSettings/fixtures)
                            _doubleRoundRobin = enabled;
                          });
                        },
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  activeColor: cs.primary,
                  checkColor: Colors.white,
                  title: Text(
                    'Home and Away Matches',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    _homeAwayEnabled ? 'Each team plays twice (home + away).' : 'Each team plays once.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.65),
                      fontSize: 12,
                      height: 1.25,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              Divider(color: cs.onSurface.withOpacity(0.12)),
              SwitchListTile.adaptive(
                value: _containsRewards,
                onChanged: _submitting ? null : (v) => setState(() => _containsRewards = v),
                activeColor: cs.primary,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Does this league contain rewards?',
                  style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  _containsRewards
                      ? 'Yes — you will be prompted to add rewards after creation.'
                      : 'No — you can add rewards later from League Admin.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurface.withOpacity(0.65),
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stepReview({Key? key}) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final canCreate = _name.text.trim().isNotEmpty && (!_creationRequiresPayment || _paymentCompleted);

    final paymentTitle =
        _paymentCompleted ? l10n.tr('league_create_payment_completed_title') : l10n.tr('league_create_payment_required_title');
    final paymentSubtitle = _paymentCompleted
        ? '${l10n.tr('league_create_receipt_prefix')} ${_payment?.receiptId ?? ''}'
        : l10n.tr('league_create_payment_required_subtitle');

    final paymentIcon = _paymentCompleted ? Icons.verified : Icons.lock_outline;
    final paymentAccent = _paymentCompleted ? cs.primary : _premiumAmber;

    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('Review', Icons.check_circle_outline),
        const SizedBox(height: 10),
        _infoBanner(
          icon: Icons.emoji_events_outlined,
          title: _name.text.trim().isEmpty ? l10n.tr('league_create_league_name_not_set') : _name.text.trim(),
          subtitle: '${_format.displayName} • $_maxTeams teams • ${_privacy == LeaguePrivacy.private ? 'Private' : 'Public'}',
        ),
        const SizedBox(height: 10),
        if (_supportsHomeAwayMatches)
          _confirmRow(
            Icons.swap_horiz,
            'Home & away matches',
            _homeAwayEnabled ? 'Enabled' : 'Disabled',
            valueColor: _homeAwayEnabled ? cs.primary : cs.onSurface.withOpacity(0.75),
          ),
        _confirmRow(
          Icons.card_giftcard_outlined,
          'Rewards',
          _containsRewards ? 'Yes' : 'No',
          valueColor: _containsRewards ? cs.primary : cs.onSurface.withOpacity(0.75),
        ),
        if (_couponsEnabled)
          _confirmRow(
            Icons.confirmation_number_outlined,
            'Coupons',
            _couponLabel.replaceFirst('Coupons: ', ''),
            valueColor: cs.primary,
          ),
        if (_creationRequiresPayment) ...[
          const SizedBox(height: 10),
          _infoBanner(
            icon: paymentIcon,
            title: paymentTitle,
            subtitle: paymentSubtitle,
            accent: paymentAccent,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _submitting ? null : _payIfNeeded,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(
              _paymentCompleted ? l10n.tr('league_create_payment_done_view_receipt') : l10n.tr('league_create_pay_now'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
        const SizedBox(height: 12),

        // Single working create button for wizard
        FilledButton(
          onPressed: (_submitting || !canCreate) ? null : () => _create(context),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
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

  Widget _buildFooterActions(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    final isLast = _step == 2;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _submitting ? null : _backOrClose,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: cs.onSurface.withOpacity(0.18)),
              foregroundColor: cs.onSurface.withOpacity(0.80),
            ),
            child: Text(
              (_step == 0 ? l10n.tr('common_cancel') : l10n.tr('common_back')).toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: (_submitting || isLast)
                ? null
                : () async {
                    await _validateAndNext();
                  },
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            child: Text(
              l10n.tr('common_next').toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  Widget _confirmRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
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

  Future<void> _create(BuildContext context) async {
    final l10n = context.l10n;

    if (_submitting) return;

    if (_name.text.trim().isEmpty) {
      _showSnack(l10n.tr('league_create_error_name_required'));
      return;
    }

    if (_creationRequiresPayment && !_paymentCompleted) {
      _showSnack(l10n.tr('league_create_error_payment_must_be_completed'));
      return;
    }

    setState(() => _submitting = true);

    try {
      final organizerUid = (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
      if (organizerUid.isEmpty) {
        throw StateError('unauthenticated');
      }

      final derivedShortId = UserProfile.deriveShareIdFromUid(organizerUid).trim();
      final organizerUserId = derivedShortId.isNotEmpty ? derivedShortId : organizerUid;

      final leagueId = _draftLeagueId;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Ensure Home/Away is only active for formats that support it
      final effectiveHomeAwayEnabled = _supportsHomeAwayMatches ? _homeAwayEnabled : false;

      final settings = LeagueSettings.defaultsFor(_format).copyWith(
        doubleRoundRobin: effectiveHomeAwayEnabled,
        lastPulledAtMs: 0,
      );

      // Keep existing flag aligned for any downstream usage inside this widget
      _doubleRoundRobin = effectiveHomeAwayEnabled;

      final couponsEnabled = _paymentCompleted && (_payment?.buyCouponsForParticipants ?? false);
      final discountPercent = (couponsEnabled ? (_payment?.couponDiscountPercent ?? 0) : 0).clamp(0, 100);
      final couponCount = couponsEnabled ? (_payment?.couponCount ?? 0) : 0;
      final safeCouponCount = couponCount < 0 ? 0 : couponCount;

      final joinCode = await _generateUniqueJoinCode().timeout(const Duration(seconds: 12));

      final league = League(
        id: leagueId,
        name: _name.text.trim(),
        description: _description.text.trim(),
        leagueImageUrl: _leagueImageUrl.text.trim(),
        sponsorImageUrl: _sponsorImageUrl.text.trim(),
        viewerCapacity: 0,
        couponsEnabled: couponsEnabled,
        couponDiscountPercent: discountPercent,
        couponCount: safeCouponCount,
        homeAwayEnabled: effectiveHomeAwayEnabled,
        format: _format,
        privacy: _privacy,
        region: l10n.tr('common_region_global'),
        maxTeams: _maxTeams,
        season: '2026',
        organizerUid: organizerUid,
        organizerUserId: organizerUserId,
        code: joinCode,
        qrPayloadOverride: '',
        settings: settings,
        updatedAtMs: now,
        version: 1,
      );

      final repo = LeaguesRepositoryFirebase();
      await repo.saveLeague(league).timeout(const Duration(seconds: 25));

      if (couponsEnabled && safeCouponCount > 0) {
        try {
          final plan = await RemotePricingService.instance
              .getPlanForLocale(Localizations.maybeLocaleOf(context))
              .timeout(const Duration(seconds: 15));

          await CouponConfigService()
              .createOrIncrementOnPurchase(
                leagueId: leagueId,
                organizerUserId: organizerUid,
                qtyPurchased: safeCouponCount,
                discountPercent: discountPercent,
                plan: plan,
              )
              .timeout(const Duration(seconds: 20));
        } catch (_) {
          _showSnack("We saved your league, but couldn't update coupons right now. Please try again.");
        }
      }

      if (!mounted) return;
      setState(() {
        _createdLeague = league;
        _submitting = false;
      });

      // NEW: Immediately offer rewards management if organizer selected Yes.
      if (_containsRewards) {
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EditLeagueRewardsScreen(leagueId: league.id),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showSnack(UserFriendlyError.toMessage(e is Object ? e : Exception('unknown')));
    }
  }
}

/// Redesigned _OptionalImageField:
/// - NO TextField displaying the URL — the Cloudinary link is NEVER visible.
/// - Shows a thumbnail preview if an image is set (from URL or base64 data URI).
/// - Shows a human-readable status label ("Image uploaded" / "No image selected").
/// - Upload and Clear buttons remain fully functional.
/// - The TextEditingController still holds the URL internally for backend submission.
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final url = controller.text.trim();
    final hasImage = url.isNotEmpty;
    final bytes = hasImage ? _tryDecodeDataUri(url) : null;

    // Thumbnail preview
    final preview = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: cs.onSurface.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasImage ? cs.primary.withOpacity(0.40) : cs.onSurface.withOpacity(0.14),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: bytes != null
            ? Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
            : (hasImage
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.broken_image_outlined,
                      color: cs.onSurface.withOpacity(0.45),
                      size: 20,
                    ),
                  )
                : Icon(
                    Icons.image_outlined,
                    color: cs.onSurface.withOpacity(0.40),
                    size: 20,
                  )),
      ),
    );

    // Status text — NEVER shows the URL
    final statusText = hasImage ? 'Image uploaded ✓' : 'No image selected';
    final statusColor = hasImage ? cs.primary : cs.onSurface.withOpacity(0.55);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: cs.onSurface.withOpacity(0.03),
        border: Border.all(color: cs.onSurface.withOpacity(0.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          preview,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  statusText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Upload button
          SizedBox(
            width: 40,
            height: 40,
            child: uploading
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                  )
                : IconButton(
                    tooltip: 'Upload image',
                    onPressed: onUpload,
                    icon: Icon(
                      Icons.cloud_upload_outlined,
                      color: cs.primary,
                    ),
                  ),
          ),
          // Clear button — only shown when an image is set
          if (hasImage)
            SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                tooltip: 'Remove image',
                onPressed: onClear,
                icon: Icon(
                  Icons.close,
                  color: cs.error.withOpacity(0.80),
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StepMeta {
  final String title;
  final IconData icon;

  const _StepMeta(this.title, this.icon);
}
