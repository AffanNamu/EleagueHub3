///master_leagues/presentation/organizer_verification_application_screen.dart
import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/payment_platform_config.dart';
import '../../../core/locale/app_localizations.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/payments/google_play_billing_service.dart';
import '../../../core/services/remote_pricing_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../domain/organizer_verification_request.dart';
import '../logic/master_leagues_providers.dart';

const List<(String code, String name)> kOrganizerVerificationCountries = [
  ('US', 'United States'), ('GB', 'United Kingdom'), ('NG', 'Nigeria'),
  ('GH', 'Ghana'), ('KE', 'Kenya'), ('ZA', 'South Africa'), ('EG', 'Egypt'),
  ('CA', 'Canada'), ('AU', 'Australia'), ('DE', 'Germany'), ('FR', 'France'),
  ('ES', 'Spain'), ('IT', 'Italy'), ('NL', 'Netherlands'), ('BE', 'Belgium'),
  ('PT', 'Portugal'), ('IE', 'Ireland'), ('SE', 'Sweden'), ('NO', 'Norway'),
  ('DK', 'Denmark'), ('FI', 'Finland'), ('PL', 'Poland'), ('CZ', 'Czechia'),
  ('AT', 'Austria'), ('CH', 'Switzerland'), ('GR', 'Greece'), ('TR', 'Turkey'),
  ('RU', 'Russia'), ('UA', 'Ukraine'), ('IN', 'India'), ('PK', 'Pakistan'),
  ('BD', 'Bangladesh'), ('CN', 'China'), ('JP', 'Japan'), ('KR', 'South Korea'),
  ('ID', 'Indonesia'), ('MY', 'Malaysia'), ('SG', 'Singapore'),
  ('PH', 'Philippines'), ('TH', 'Thailand'), ('VN', 'Vietnam'),
  ('AE', 'United Arab Emirates'), ('SA', 'Saudi Arabia'), ('QA', 'Qatar'),
  ('IL', 'Israel'), ('BR', 'Brazil'), ('AR', 'Argentina'), ('MX', 'Mexico'),
  ('CL', 'Chile'), ('CO', 'Colombia'), ('PE', 'Peru'), ('CM', 'Cameroon'),
  ('CI', "Cote d'Ivoire"), ('SN', 'Senegal'), ('TZ', 'Tanzania'),
  ('UG', 'Uganda'), ('RW', 'Rwanda'), ('ET', 'Ethiopia'), ('MA', 'Morocco'),
  ('DZ', 'Algeria'), ('TN', 'Tunisia'), ('ZM', 'Zambia'), ('ZW', 'Zimbabwe'),
  ('NZ', 'New Zealand'), ('HU', 'Hungary'), ('RO', 'Romania'),
  ('BG', 'Bulgaria'), ('HR', 'Croatia'), ('RS', 'Serbia'), ('SK', 'Slovakia'),
  ('SI', 'Slovenia'), ('IS', 'Iceland'), ('LU', 'Luxembourg'), ('CY', 'Cyprus'),
  ('MT', 'Malta'),
];

const List<String> kOrganizerTypes = [
  'Esports Organization',
  'Football Club / Academy',
  'League / Federation',
  'Community / Fan Group',
  'Company / Brand',
  'Educational Institution',
  'Individual Organizer',
  'Other',
];

class OrganizerVerificationApplicationScreen extends ConsumerStatefulWidget {
  const OrganizerVerificationApplicationScreen({
    super.key,
    required this.masterLeagueId,
    required this.masterLeagueName,
  });

  final String masterLeagueId;
  final String masterLeagueName;

  @override
  ConsumerState<OrganizerVerificationApplicationScreen> createState() =>
      _OrganizerVerificationApplicationScreenState();
}

class _OrganizerVerificationApplicationScreenState
    extends ConsumerState<OrganizerVerificationApplicationScreen> {
  static const int _maxLogoBytes = 5 * 1024 * 1024;

  int _stepIndex = 0;
  bool _hydrated = false;
  bool _submitting = false;
  bool _uploadingLogo = false;
  bool _agreed = false;

  double? _feeAmount;
  String _feeCurrency = '';
  // NEW (bug #5 fix): when the price is sourced from Google Play
  // Billing (Android), we display the exact, already-localized string
  // Play Store itself returns (e.g. "$4.99", "₦4,500.00") instead of
  // formatting _feeAmount/_feeCurrency ourselves. Left null when the
  // price came from RemotePricingService instead.
  String? _feeFormatted;

  OrganizerVerificationRequest? _existingRequest;

  final _orgNameCtrl = TextEditingController();
  final _orgRegionCtrl = TextEditingController();
  final _orgCityCtrl = TextEditingController();
  final _contactEmailCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _socialLinkCtrl = TextEditingController();
  final _applicantNameCtrl = TextEditingController();
  final _applicantRoleCtrl = TextEditingController();
  final _orgDescriptionCtrl = TextEditingController();
  final _competitionTypesCtrl = TextEditingController();
  final _verificationReasonCtrl = TextEditingController();
  final _supportingLinksCtrl = TextEditingController();

  String _orgType = kOrganizerTypes.first;
  String _orgCountry = '';
  String _logoUrl = '';

  bool _pricingLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pricingLoaded) {
      _pricingLoaded = true;
      _loadPricing();
    }
  }

  // FIXED (bug #5 -- root cause): this previously ALWAYS pulled from
  // RemotePricingService, which reflects the Flutterwave/web pricing
  // config document in Firestore. On Android, though, the actual charge
  // for organizer verification goes through Google Play Billing (see
  // MasterLeaguePaymentService._purchaseVerificationViaGooglePlay()),
  // whose price is whatever is configured for the
  // `organizer_verification` product in Play Console -- a completely
  // different number/currency than the Firestore doc, and shown as
  // "0.00 NGN" whenever that doc's organizerVerificationFee happened to
  // be unset for the resolved currency. The working Pro/Elite purchase
  // screen avoids this by calling GooglePlayBillingService.fetchPlanPrice()
  // to get the live Play Store price on Android; this screen now does
  // the equivalent via fetchOrganizerVerificationPrice(), falling back
  // to RemotePricingService only when Google Play pricing isn't the
  // active route (e.g. web) or the Play Store query itself fails.
  Future<void> _loadPricing() async {
    try {
      if (PaymentPlatformConfig.routeAndroidPaymentsToGooglePlayBilling) {
        final info = await GooglePlayBillingService.instance
            .fetchOrganizerVerificationPrice();
        if (info != null) {
          if (!mounted) return;
          setState(() {
            _feeAmount = info.rawPrice;
            _feeCurrency = info.currencyCode;
            _feeFormatted = info.formattedPrice;
          });
          return;
        }
      }

      final plan = await RemotePricingService.instance.getPlanForLocale(
        Localizations.maybeLocaleOf(context),
      );
      if (!mounted) return;
      setState(() {
        _feeAmount = plan.organizerVerificationFee;
        _feeCurrency = plan.currency;
        _feeFormatted = null;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _orgNameCtrl.dispose();
    _orgRegionCtrl.dispose();
    _orgCityCtrl.dispose();
    _contactEmailCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _websiteCtrl.dispose();
    _socialLinkCtrl.dispose();
    _applicantNameCtrl.dispose();
    _applicantRoleCtrl.dispose();
    _orgDescriptionCtrl.dispose();
    _competitionTypesCtrl.dispose();
    _verificationReasonCtrl.dispose();
    _supportingLinksCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  bool get _isResubmission =>
      _existingRequest?.statusEnum == VerificationRequestStatus.infoRequested;

  bool get _blockedByExistingRequest {
    final s = _existingRequest?.statusEnum;
    return s == VerificationRequestStatus.pending ||
        s == VerificationRequestStatus.approved;
  }

  void _hydrateFrom(OrganizerVerificationRequest? req) {
    if (_hydrated) return;
    _hydrated = true;
    _existingRequest = req;
    if (req == null || req.isLegacyPaymentOnly) return;
    if (req.statusEnum != VerificationRequestStatus.infoRequested) return;

    _orgNameCtrl.text = req.orgName;
    _orgType = kOrganizerTypes.contains(req.orgType)
        ? req.orgType
        : kOrganizerTypes.first;
    _orgCountry = req.orgCountry;
    _orgRegionCtrl.text = req.orgRegion;
    _orgCityCtrl.text = req.orgCity;
    _contactEmailCtrl.text = req.contactEmail;
    _contactPhoneCtrl.text = req.contactPhone;
    _websiteCtrl.text = req.website;
    _socialLinkCtrl.text = req.socialLink;
    _applicantNameCtrl.text = req.applicantFullName;
    _applicantRoleCtrl.text = req.applicantRole;
    _orgDescriptionCtrl.text = req.orgDescription;
    _competitionTypesCtrl.text = req.competitionTypes;
    _verificationReasonCtrl.text = req.verificationReason;
    _supportingLinksCtrl.text = req.supportingLinks;
    _logoUrl = req.logoUrl;
  }

  OrganizerVerificationApplicationData _buildApplicationData() {
    return OrganizerVerificationApplicationData(
      orgName: _orgNameCtrl.text,
      orgType: _orgType,
      orgCountry: _orgCountry,
      orgRegion: _orgRegionCtrl.text,
      orgCity: _orgCityCtrl.text,
      contactEmail: _contactEmailCtrl.text,
      contactPhone: _contactPhoneCtrl.text,
      website: _websiteCtrl.text,
      socialLink: _socialLinkCtrl.text,
      applicantFullName: _applicantNameCtrl.text,
      applicantRole: _applicantRoleCtrl.text,
      orgDescription: _orgDescriptionCtrl.text,
      competitionTypes: _competitionTypesCtrl.text,
      verificationReason: _verificationReasonCtrl.text,
      supportingLinks: _supportingLinksCtrl.text,
      logoUrl: _logoUrl,
    );
  }

  // ── Logo upload (Cloudinary, same pattern as OrganizerProfileScreen) ────

  Future<String> _uploadToCloudinary(PlatformFile picked) async {
    final cloudName =
        const String.fromEnvironment('CLOUDINARY_CLOUD_NAME').trim();
    final uploadPreset =
        const String.fromEnvironment('CLOUDINARY_UNSIGNED_UPLOAD_PRESET')
            .trim();
    if (cloudName.isEmpty || uploadPreset.isEmpty) {
      throw StateError('Cloudinary is not configured.');
    }

    final uploadUrl = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );
    final ts = DateTime.now().millisecondsSinceEpoch;

    http.MultipartFile filePart;
    final bytes = picked.bytes;
    final path = (picked.path ?? '').trim();

    if (bytes != null && bytes.isNotEmpty) {
      filePart = http.MultipartFile.fromBytes('file', bytes,
          filename: picked.name);
    } else if (path.isNotEmpty) {
      filePart =
          await http.MultipartFile.fromPath('file', path, filename: picked.name);
    } else {
      throw StateError('Selected image is not accessible.');
    }

    final req = http.MultipartRequest('POST', uploadUrl)
      ..fields['upload_preset'] = uploadPreset
      ..fields['resource_type'] = 'image'
      ..fields['folder'] = 'eleaguehub/organizer_verification'
      ..fields['public_id'] = 'verification_logo_${widget.masterLeagueId}_$ts'
      ..files.add(filePart);

    final client = http.Client();
    try {
      final streamed = await client.send(req).timeout(const Duration(seconds: 45));
      final resp = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 45));

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        String message = 'Upload failed (HTTP ${resp.statusCode}).';
        try {
          final decoded = jsonDecode(resp.body);
          final err = (decoded is Map<String, dynamic>) ? decoded['error'] : null;
          final msg = (err is Map<String, dynamic>)
              ? (err['message']?.toString() ?? '')
              : '';
          if (msg.trim().isNotEmpty) message = 'Upload failed: ${msg.trim()}';
        } catch (_) {}
        throw StateError(message);
      }

      final decoded = jsonDecode(resp.body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('Upload failed: invalid response.');
      }
      final secureUrl = (decoded['secure_url']?.toString() ?? '').trim();
      if (secureUrl.isEmpty) throw StateError('Upload failed: secure_url missing.');
      return secureUrl;
    } on TimeoutException {
      throw StateError('Upload timed out. Please try again.');
    } finally {
      client.close();
    }
  }

  Future<void> _pickAndUploadLogo() async {
    if (_uploadingLogo) return;
    setState(() => _uploadingLogo = true);
    try {
      await ConnectivityService.instance.requireOnline(timeout: const Duration(seconds: 6));
      final pickResult = await SafeImagePicker.pickImage();
      if (pickResult.wasCancelled) return;
      if (!pickResult.isSuccess) {
        _snack(pickResult.errorMessage ?? context.l10n.tr('organizer_verification_error_pick_image'), error: true);
        return;
      }
      final picked = pickResult.file!;
      if (picked.size > _maxLogoBytes) {
        _snack(context.l10n.tr('organizer_verification_error_logo_too_large'), error: true);
        return;
      }
      final url = await _uploadToCloudinary(picked);
      if (!mounted) return;
      setState(() => _logoUrl = url);
    } catch (e) {
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _uploadingLogo = false);
    }
  }

  // ── Submission ────────────────────────────────────────────────────────

  int? _stepIndexForField(String field) {
    const step0 = {'orgName', 'orgType', 'orgCountry'};
    const step1 = {'contactEmail', 'applicantFullName', 'applicantRole'};
    const step2 = {'logoUrl'};
    const step3 = {'orgDescription', 'verificationReason'};
    if (step0.contains(field)) return 0;
    if (step1.contains(field)) return 1;
    if (step2.contains(field)) return 2;
    if (step3.contains(field)) return 3;
    return null;
  }

  Future<void> _handleSubmit() async {
    final application = _buildApplicationData();
    final validationError = application.validate();
    if (validationError != null) {
      _snack(validationError, error: true);
      return;
    }
    if (!_agreed) {
      _snack(context.l10n.tr('organizer_verification_error_confirm_fee'), error: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final repo = ref.read(masterLeaguesRepositoryProvider);

      if (_isResubmission && _existingRequest != null) {
        await repo.resubmitVerificationApplication(
          masterLeagueId: widget.masterLeagueId,
          requestId: _existingRequest!.requestId,
          application: application,
        );
        if (!mounted) return;
        _snack(context.l10n.tr('organizer_verification_success_resubmitted'));
        Navigator.of(context).pop(true);
        return;
      }

      final paymentSvc = ref.read(masterLeaguePaymentServiceProvider);
      final userId = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

      final payment = await paymentSvc.payForOrganizerVerification(
        context: context,
        userId: userId,
        masterLeagueId: widget.masterLeagueId,
        masterLeagueName: widget.masterLeagueName,
      );

      if (!mounted) return;
      if (!payment.success) {
        _snack(payment.errorMessage ?? context.l10n.tr('organizer_verification_error_payment_failed'), error: true);
        return;
      }

      await repo.submitVerificationApplication(
        masterLeagueId: widget.masterLeagueId,
        attemptId: payment.attemptId,
        paymentId: payment.paymentId,
        receiptId: payment.receiptId ?? '',
        application: application,
      );

      if (!mounted) return;
      _snack(context.l10n.tr('organizer_verification_success_submitted'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('$e', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OrganizerVerificationRequest?>(
      stream: ref
          .read(masterLeaguesRepositoryProvider)
          .watchLatestVerificationRequest(widget.masterLeagueId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const GlassScaffold(
            appBar: null,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        _hydrateFrom(snap.data);

        final brightness = Theme.of(context).brightness;

        return GlassScaffold(
          appBar: AppBar(
            title: Text(_isResubmission
                ? context.l10n.tr('organizer_verification_title_resubmit')
                : context.l10n.tr('organizer_verification_title_new')),
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
          body: SafeArea(
            child: _blockedByExistingRequest
                ? _buildBlockedState(brightness)
                : _buildForm(brightness),
          ),
        );
      },
    );
  }

  Widget _buildBlockedState(Brightness brightness) {
    final approved =
        _existingRequest?.statusEnum == VerificationRequestStatus.approved;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Glass(
          borderRadius: 24,
          padding: const EdgeInsets.all(20),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                approved ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                color: const Color(0xFF1D9BF0),
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                approved
                    ? context.l10n.tr('organizer_verification_blocked_approved')
                    : context.l10n.tr('organizer_verification_blocked_pending'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.primaryText(brightness),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(Brightness brightness) {
    final l10n = context.l10n;
    final steps = [
      _buildOrgIdentityStep(brightness),
      _buildApplicantStep(brightness),
      _buildBrandingStep(brightness),
      _buildAdditionalInfoStep(brightness),
      _buildReviewStep(brightness),
    ];
    final titles = [
      l10n.tr('organizer_verification_step_org_identity'),
      l10n.tr('organizer_verification_step_applicant_info'),
      l10n.tr('organizer_verification_step_branding'),
      l10n.tr('organizer_verification_step_additional_info'),
      l10n.tr('organizer_verification_step_review'),
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: List.generate(steps.length, (i) {
              final active = i <= _stepIndex;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: active
                        ? AppTheme.limeAccentDark
                        : AppTheme.cardBorder(brightness),
                  ),
                ),
              );
            }),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${l10n.tr('organizer_verification_step_progress_prefix')} ${_stepIndex + 1} '
              '${l10n.tr('organizer_verification_step_progress_of')} ${steps.length} '
              '\u00b7 ${titles[_stepIndex]}',
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: steps[_stepIndex],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: [
              if (_stepIndex > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _stepIndex -= 1),
                    child: Text(l10n.tr('common_back')),
                  ),
                ),
              if (_stepIndex > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                  ),
                  onPressed: _submitting
                      ? null
                      : () {
                          if (_stepIndex < steps.length - 1) {
                            setState(() => _stepIndex += 1);
                          } else {
                            _handleSubmit();
                          }
                        },
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _stepIndex < steps.length - 1
                              ? l10n.tr('common_continue')
                              : (_isResubmission
                                  ? l10n.tr('organizer_verification_button_resubmit')
                                  : l10n.tr('organizer_verification_button_continue_to_payment')),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(Brightness brightness, {required List<Widget> children}) {
    return Glass(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      fill: AppTheme.cardColor(brightness),
      borderColor: AppTheme.cardBorder(brightness),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 1, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label, alignLabelWithHint: maxLines > 1),
      ),
    );
  }

  Widget _buildOrgIdentityStep(Brightness brightness) {
    final l10n = context.l10n;
    return _card(brightness, children: [
      _field(_orgNameCtrl, l10n.tr('organizer_verification_field_org_name')),
      DropdownButtonFormField<String>(
        value: _orgType,
        decoration: InputDecoration(labelText: l10n.tr('organizer_verification_field_org_type')),
        items: kOrganizerTypes
            .map((t) => DropdownMenuItem(value: t, child: Text(t)))
            .toList(),
        onChanged: (v) => setState(() => _orgType = v ?? _orgType),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: _orgCountry.isEmpty ? null : _orgCountry,
        decoration: InputDecoration(labelText: l10n.tr('organizer_verification_field_country')),
        items: kOrganizerVerificationCountries
            .map((c) => DropdownMenuItem(value: c.$1, child: Text(c.$2)))
            .toList(),
        onChanged: (v) => setState(() => _orgCountry = v ?? ''),
      ),
      const SizedBox(height: 12),
      _field(_orgRegionCtrl, l10n.tr('organizer_verification_field_state_region')),
      _field(_orgCityCtrl, l10n.tr('organizer_verification_field_city')),
    ]);
  }

  Widget _buildApplicantStep(Brightness brightness) {
    final l10n = context.l10n;
    return _card(brightness, children: [
      _field(_applicantNameCtrl, l10n.tr('organizer_verification_field_applicant_name')),
      _field(_applicantRoleCtrl, l10n.tr('organizer_verification_field_applicant_role')),
      _field(_contactEmailCtrl, l10n.tr('organizer_verification_field_contact_email'), keyboardType: TextInputType.emailAddress),
      _field(_contactPhoneCtrl, l10n.tr('organizer_verification_field_contact_phone'), keyboardType: TextInputType.phone),
      _field(_websiteCtrl, l10n.tr('organizer_verification_field_website')),
      _field(_socialLinkCtrl, l10n.tr('organizer_verification_field_social_link')),
    ]);
  }

  Widget _buildBrandingStep(Brightness brightness) {
    final l10n = context.l10n;
    return _card(brightness, children: [
      Text(
        l10n.tr('organizer_verification_branding_logo_label'),
        style: TextStyle(
          color: AppTheme.primaryText(brightness),
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        l10n.tr('organizer_verification_branding_logo_hint'),
        style: TextStyle(color: AppTheme.secondaryText(brightness), fontSize: 12),
      ),
      const SizedBox(height: 14),
      Center(
        child: InkWell(
          onTap: _pickAndUploadLogo,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.iconCircleBackground(brightness),
              border: Border.all(color: AppTheme.cardBorder(brightness)),
            ),
            child: _uploadingLogo
                ? const Center(child: CircularProgressIndicator())
                : (_logoUrl.isNotEmpty
                    ? ClipOval(child: Image.network(_logoUrl, fit: BoxFit.cover))
                    : Icon(Icons.add_a_photo_outlined,
                        color: AppTheme.limeAccentDark, size: 32)),
          ),
        ),
      ),
      const SizedBox(height: 10),
      Center(
        child: TextButton(
          onPressed: _uploadingLogo ? null : _pickAndUploadLogo,
          child: Text(_logoUrl.isEmpty
              ? l10n.tr('organizer_verification_branding_upload_logo')
              : l10n.tr('organizer_verification_branding_change_logo')),
        ),
      ),
    ]);
  }

  Widget _buildAdditionalInfoStep(Brightness brightness) {
    final l10n = context.l10n;
    return _card(brightness, children: [
      _field(_orgDescriptionCtrl, l10n.tr('organizer_verification_field_org_description'), maxLines: 4),
      _field(_competitionTypesCtrl, l10n.tr('organizer_verification_field_competition_types'), maxLines: 3),
      _field(_verificationReasonCtrl, l10n.tr('organizer_verification_field_verification_reason'), maxLines: 4),
      _field(_supportingLinksCtrl, l10n.tr('organizer_verification_field_supporting_links'), maxLines: 3),
    ]);
  }

  Widget _buildReviewStep(Brightness brightness) {
    final l10n = context.l10n;
    // FIXED (bug #5): prefer the live, already-localized Google Play
    // Store price string when we have one; only fall back to manually
    // formatting _feeAmount/_feeCurrency (RemotePricingService's value)
    // when Google Play pricing wasn't used/available.
    final feeLabel = _feeFormatted != null
        ? _feeFormatted!
        : (_feeAmount == null
            ? l10n.tr('organizer_verification_loading_fee')
            : '${_feeAmount!.toStringAsFixed(2)} $_feeCurrency');

    return _card(brightness, children: [
      Text(
        l10n.tr('organizer_verification_review_title'),
        style: TextStyle(
          color: AppTheme.primaryText(brightness),
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
      const SizedBox(height: 10),
      _reviewRow(brightness, l10n.tr('organizer_verification_review_org_label'), _orgNameCtrl.text),
      _reviewRow(brightness, l10n.tr('organizer_verification_review_type_label'), _orgType),
      _reviewRow(
        brightness,
        l10n.tr('organizer_verification_review_country_label'),
        kOrganizerVerificationCountries
            .firstWhere((c) => c.$1 == _orgCountry, orElse: () => ('', '\u2014'))
            .$2,
      ),
      _reviewRow(brightness, l10n.tr('organizer_verification_review_applicant_label'), _applicantNameCtrl.text),
      _reviewRow(brightness, l10n.tr('organizer_verification_review_contact_email_label'), _contactEmailCtrl.text),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.error.withOpacity(0.08),
          border: Border.all(
            color: Theme.of(context).colorScheme.error.withOpacity(0.28),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.tr('organizer_verification_fee_warning_title'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${l10n.tr('organizer_verification_fee_notice_prefix')} '
              '$feeLabel ${l10n.tr('organizer_verification_fee_notice_suffix')}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
                height: 1.4,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => _agreed = !_agreed),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _agreed,
                    onChanged: (v) => setState(() => _agreed = v ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _isResubmission
                            ? l10n.tr('organizer_verification_agree_resubmit_text')
                            : '${l10n.tr('organizer_verification_agree_fee_prefix')} $feeLabel '
                                '${l10n.tr('organizer_verification_agree_fee_suffix')}',
                        style: TextStyle(
                          color: AppTheme.primaryText(brightness),
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _reviewRow(Brightness brightness, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: AppTheme.secondaryText(brightness),
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '\u2014' : value,
              style: TextStyle(
                  color: AppTheme.primaryText(brightness),
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}