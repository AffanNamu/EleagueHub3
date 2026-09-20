import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/locale/app_localizations.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/services/cloudinary_upload_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/safe_image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/auth_service.dart';
import '../data/user_profile_repository.dart';
import '../domain/username_utils.dart';

enum _UsernameFieldStatus {
  idle,
  checking,
  available,
  taken,
  invalid,
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final UserProfileRepository _profiles = UserProfileRepository();
  final TextEditingController _teamNameCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();

  final CloudinaryUploadService _cloudinary = CloudinaryUploadService();

  // Same limit ProfileScreen enforces before handing a picked file to
  // CloudinaryUploadService — kept local since the shared service
  // itself doesn't impose a size cap.
  static const int _maxImageBytes = 5 * 1024 * 1024;

  bool _saving = false;
  int _step = 0;

  String _game = '';
  String _experience = '';
  String _goal = '';

  // ─── Username live-check state ─────────────────────────────────────────────
  _UsernameFieldStatus _usernameStatus = _UsernameFieldStatus.idle;
  String? _usernameError;
  Timer? _usernameDebounce;
  int _usernameCheckToken = 0;

  // ─── Profile / team image state (optional — user can skip) ────────────────
  bool _uploadingImage = false;
  String? _uploadedImageUrl;
  String? _imageError;

  // ─── Game catalogue ────────────────────────────────────────────────────────

  static const _gameGroups = <_GameGroup>[
    _GameGroup(
      label: 'auth_onboarding_game_group_console_pc',
      icon: Icons.sports_esports,
      games: [
        'EA Sports FC 25',
        'FIFA 23',
        'eFootball',
        'PES 2021',
        'PES 2017',
        'UFL',
        'Rocket League',
      ],
    ),
    _GameGroup(
      label: 'auth_onboarding_game_group_mobile',
      icon: Icons.smartphone,
      games: [
        'EA Sports FC Mobile',
        'Dream League Soccer',
        'Soccer Stars',
        'Total Football',
        'Football Strike',
        'Mini Football',
        'Score! Match',
      ],
    ),
  ];

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _usernameCtrl.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameCtrl.removeListener(_onUsernameChanged);
    _teamNameCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildOnboardingAnswers() => <String, dynamic>{
        'game': _game,
        'experience': _experience,
        'goal': _goal,
        'category': 'football',
      };

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  // ── Username: debounced live availability check ────────────────────────────

  void _onUsernameChanged() {
    _usernameDebounce?.cancel();

    final raw = _usernameCtrl.text.trim().toLowerCase();

    if (raw.isEmpty) {
      setState(() {
        _usernameStatus = _UsernameFieldStatus.idle;
        _usernameError = null;
      });
      return;
    }

    if (!UsernameUtils.isValidFormat(raw)) {
      setState(() {
        _usernameStatus = _UsernameFieldStatus.invalid;
        _usernameError = raw.length < UsernameUtils.minLength ||
                raw.length > UsernameUtils.maxLength
            ? "${context.l10n.tr('auth_onboarding_username_length_error_prefix')}"
                "${UsernameUtils.minLength}-${UsernameUtils.maxLength}"
                "${context.l10n.tr('auth_onboarding_username_length_error_suffix')}"
            : context.l10n.tr('auth_onboarding_username_format_error');
      });
      return;
    }

    if (UsernameUtils.isReserved(raw)) {
      setState(() {
        _usernameStatus = _UsernameFieldStatus.invalid;
        _usernameError = context.l10n.tr('auth_onboarding_username_reserved_error');
      });
      return;
    }

    setState(() {
      _usernameStatus = _UsernameFieldStatus.checking;
      _usernameError = null;
    });

    final token = ++_usernameCheckToken;
    _usernameDebounce = Timer(const Duration(milliseconds: 450), () {
      _checkUsernameAvailability(raw, token);
    });
  }

  Future<void> _checkUsernameAvailability(String raw, int token) async {
    try {
      final available = await _profiles.isUsernameAvailable(raw);
      if (!mounted || token != _usernameCheckToken) return;
      setState(() {
        _usernameStatus = available
            ? _UsernameFieldStatus.available
            : _UsernameFieldStatus.taken;
        _usernameError = available
            ? null
            : context.l10n.tr('auth_onboarding_username_taken_error');
      });
    } catch (e) {
      if (!mounted || token != _usernameCheckToken) return;
      setState(() {
        _usernameStatus = _UsernameFieldStatus.invalid;
        _usernameError = '$e';
      });
    }
  }

  bool get _usernameIsReady =>
      _usernameStatus == _UsernameFieldStatus.available;

  // ── Profile / team image: pick + upload immediately, skip if declined ─────

  Future<void> _pickAndUploadImage() async {
    if (_uploadingImage) return;

    setState(() {
      _uploadingImage = true;
      _imageError = null;
    });

    try {
      await ConnectivityService.instance
          .requireOnline(timeout: const Duration(seconds: 6));

      final pickResult = await SafeImagePicker.pickImage();

      if (pickResult.wasCancelled) return;

      if (!pickResult.isSuccess) {
        setState(() {
          _imageError = pickResult.errorMessage ??
              context.l10n.tr('auth_onboarding_pick_image_failed');
        });
        return;
      }

      final picked = pickResult.file!;

      if (picked.size > _maxImageBytes) {
        setState(() {
          _imageError =
              context.l10n.tr('auth_onboarding_image_too_large_error');
        });
        return;
      }

      // Same service, same destination folder ProfileScreen uses for
      // avatars — an image picked here and one changed later from the
      // profile screen land in the exact same place.
      final secureUrl = await _cloudinary.uploadImagePlatformFile(
        file: picked,
        folder: 'eleaguehub/users',
      );

      if (!mounted) return;
      setState(() => _uploadedImageUrl = secureUrl);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _imageError =
          e.message ?? context.l10n.tr('auth_onboarding_pick_image_failed'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _imageError = '$e');
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  void _removePickedImage() {
    setState(() {
      _uploadedImageUrl = null;
      _imageError = null;
    });
  }

  // ── Finish ──────────────────────────────────────────────────────────────

  Future<void> _finish() async {
    if (_saving) return;

    final teamName = _teamNameCtrl.text.trim();
    if (teamName.isEmpty) {
      _snack(context.l10n.tr('auth_onboarding_team_name_required'));
      return;
    }

    if (!_usernameIsReady) {
      _snack(context.l10n.tr('auth_onboarding_username_not_ready'));
      return;
    }

    setState(() => _saving = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final provider = currentUser != null
          ? AuthService.detectAuthProvider(currentUser)
          : 'email';

      await _profiles.completeOnboarding(
        teamName: teamName,
        username: _usernameCtrl.text.trim(),
        authProvider: provider,
        imageUrl: _uploadedImageUrl,
        onboardingAnswers: _buildOnboardingAnswers(),
      );

      // Onboarding is now fully persisted (profile doc + username, and
      // the image if one was added) — only now is it safe to let the
      // router know the user no longer needs onboarding. Without this,
      // AuthRouterRefresh's cached profile state would still say
      // "missing" (it only re-checks on auth-state changes or an
      // explicit refresh like this one) and `context.go('/')` below
      // would immediately get redirected straight back to /onboarding.
      await authRouterRefresh.refreshProfileStatus();

      if (!mounted) return;
      context.go('/');
    } catch (e) {
      if (!mounted) return;
      _snack('$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Widget builders ───────────────────────────────────────────────────────

  Widget _choiceChip({
    required String label,
    required String groupValue,
    required ValueChanged<String> onSelected,
    IconData? icon,
  }) {
    final brightness = Theme.of(context).brightness;
    final selected = groupValue == label;

    return ChoiceChip(
      avatar: icon != null
          ? Icon(
              icon,
              size: 18,
              color: selected
                  ? AppTheme.darkText
                  : AppTheme.tabInactiveText(brightness),
            )
          : null,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(label),
      selectedColor: AppTheme.limeAccent,
      backgroundColor: AppTheme.tabInactiveBackground(brightness),
      labelStyle: TextStyle(
        color: selected
            ? AppTheme.darkText
            : AppTheme.tabInactiveText(brightness),
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      side: BorderSide(
        color: selected
            ? AppTheme.limeAccentDark
            : AppTheme.cardBorder(brightness),
      ),
    );
  }

  Step _stepCard({
    required BuildContext context,
    required String title,
    required Widget content,
    required bool active,
    String? subtitle,
  }) {
    final brightness = Theme.of(context).brightness;

    return Step(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppTheme.primaryText(brightness),
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: AppTheme.secondaryText(brightness),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
      isActive: active,
      content: Glass(
        borderRadius: 20,
        padding: const EdgeInsets.all(14),
        fill: AppTheme.cardColor(brightness),
        borderColor: AppTheme.cardBorder(brightness),
        child: content,
      ),
    );
  }

  Widget _sectionTitle(String text) {
    final brightness = Theme.of(context).brightness;
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: AppTheme.primaryText(brightness),
      ),
    );
  }

  /// Renders a labelled group header for game categories.
  Widget _groupHeader(String label, IconData icon) {
    final brightness = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.secondaryText(brightness)),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.secondaryText(brightness),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: AppTheme.cardBorder(brightness),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the full game-picker widget with grouped categories.
  Widget _gamePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context.l10n.tr('auth_onboarding_select_game_title')),
        ..._gameGroups.map((group) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _groupHeader(context.l10n.tr(group.label), group.icon),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: group.games
                      .map(
                        (game) => _choiceChip(
                          label: game,
                          icon: group.icon,
                          groupValue: _game,
                          onSelected: (v) => setState(() => _game = v),
                        ),
                      )
                      .toList(),
                ),
              ],
            )),
      ],
    );
  }

  Widget _usernameField() {
    final brightness = Theme.of(context).brightness;

    Widget? suffix;
    switch (_usernameStatus) {
      case _UsernameFieldStatus.checking:
        suffix = const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
        break;
      case _UsernameFieldStatus.available:
        suffix =
            const Icon(Icons.check_circle_rounded, color: Colors.green);
        break;
      case _UsernameFieldStatus.taken:
      case _UsernameFieldStatus.invalid:
        suffix = Icon(Icons.error_rounded,
            color: Theme.of(context).colorScheme.error);
        break;
      case _UsernameFieldStatus.idle:
        suffix = null;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context.l10n.tr('auth_onboarding_username_section_title')),
        const SizedBox(height: 4),
        Text(
          context.l10n.tr('auth_onboarding_username_description'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.secondaryText(brightness),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _usernameCtrl,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
          ],
          decoration: InputDecoration(
            labelText: context.l10n.tr('auth_onboarding_username_label'),
            hintText: context.l10n.tr('auth_onboarding_username_hint'),
            prefixText: '@',
            suffixIcon: suffix,
            errorText: _usernameError,
          ),
        ),
      ],
    );
  }

  Widget _imageStep() {
    final brightness = Theme.of(context).brightness;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context.l10n.tr('auth_onboarding_photo_section_title')),
        const SizedBox(height: 4),
        Text(
          context.l10n.tr('auth_onboarding_photo_description'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.secondaryText(brightness),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Column(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: _uploadingImage ? null : _pickAndUploadImage,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: AppTheme.fabGlow(brightness),
                  ),
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor:
                        AppTheme.iconCircleBackground(brightness),
                    child: ClipOval(
                      child: SizedBox(
                        width: 88,
                        height: 88,
                        child: _uploadingImage
                            ? const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : (_uploadedImageUrl != null)
                                ? Image.network(
                                    _uploadedImageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(
                                      Icons.person,
                                      size: 40,
                                    ),
                                  )
                                : const Icon(
                                    Icons.add_a_photo_rounded,
                                    size: 32,
                                  ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_uploadedImageUrl != null)
                TextButton(
                  onPressed: _uploadingImage ? null : _removePickedImage,
                  child: Text(context.l10n.tr('auth_onboarding_remove_photo')),
                )
              else
                Text(
                  context.l10n.tr('auth_onboarding_photo_hint'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.secondaryText(brightness),
                  ),
                ),
              if (_imageError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _imageError!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    final canContinueStep0 =
        _teamNameCtrl.text.trim().isNotEmpty && _usernameIsReady;
    // Step 1 (image) has no gating — it's optional/skippable.
    final canContinueStep2 = _game.trim().isNotEmpty;
    final canContinueStep3 = _experience.trim().isNotEmpty;
    const lastStep = 4;

    return GlassScaffold(
      appBar: AppBar(title: Text(context.l10n.tr('auth_onboarding_appbar_title'))),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Glass(
                borderRadius: 28,
                padding: const EdgeInsets.all(8),
                fill: AppTheme.cardColor(brightness),
                borderColor: AppTheme.cardBorder(brightness),
                child: Stepper(
                  type: StepperType.vertical,
                  elevation: 0,
                  currentStep: _step,
                  // ── Controls ──────────────────────────────────────────────
                  controlsBuilder: (context, details) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Row(
                        children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.limeAccent,
                              foregroundColor: AppTheme.darkText,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 14,
                              ),
                            ),
                            onPressed:
                                _saving ? null : details.onStepContinue,
                            child: _saving && _step == lastStep
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.darkText,
                                    ),
                                  )
                                : Text(
                                    _step == lastStep
                                        ? context.l10n
                                            .tr('auth_onboarding_complete_setup')
                                        : (_step == 1 &&
                                                _uploadedImageUrl == null
                                            ? context.l10n
                                                .tr('auth_onboarding_skip')
                                            : context.l10n
                                                .tr('common_continue')),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: _saving ? null : details.onStepCancel,
                            child: Text(
                              _step == 0
                                  ? context.l10n.tr('auth_onboarding_close')
                                  : context.l10n.tr('common_back'),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  // ── Navigation ────────────────────────────────────────────
                  // Mandatory onboarding, so there is no bypass here: the
                  // username step (0) can only advance once
                  // `_usernameIsReady` is true, and no step lets the user
                  // jump past it. The image step (1) is the sole
                  // intentionally-optional step — Continue doubles as
                  // "Skip" there whenever nothing has been uploaded.
                  onStepContinue: () {
                    if (_step == 0 && canContinueStep0) {
                      setState(() => _step = 1);
                      return;
                    }
                    if (_step == 1) {
                      setState(() => _step = 2);
                      return;
                    }
                    if (_step == 2 && canContinueStep2) {
                      setState(() => _step = 3);
                      return;
                    }
                    if (_step == 3 && canContinueStep3) {
                      setState(() => _step = 4);
                      return;
                    }
                    if (_step == lastStep) _finish();
                  },
                  onStepCancel: () {
                    if (_step == 0) {
                      // Mandatory onboarding has nowhere to "close" back
                      // to — there is no main-app route to return to yet.
                      return;
                    }
                    setState(() => _step -= 1);
                  },
                  // ── Steps ─────────────────────────────────────────────────
                  steps: [
                    // Step 0 – Identity (team/gamer name + username)
                    _stepCard(
                      context: context,
                      title: context.l10n.tr('auth_onboarding_step_identity_title'),
                      subtitle: context.l10n
                          .tr('auth_onboarding_step_identity_subtitle'),
                      active: _step >= 0,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(context.l10n.tr('auth_onboarding_club_name_section_title')),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _teamNameCtrl,
                            decoration: InputDecoration(
                              labelText: context.l10n.tr('auth_onboarding_club_name_label'),
                              hintText: context.l10n.tr('auth_onboarding_club_name_hint'),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 20),
                          _usernameField(),
                        ],
                      ),
                    ),

                    // Step 1 – Profile / Team Photo (optional)
                    _stepCard(
                      context: context,
                      title: context.l10n.tr('auth_onboarding_step_photo_title'),
                      subtitle:
                          context.l10n.tr('auth_onboarding_step_photo_subtitle'),
                      active: _step >= 1,
                      content: _imageStep(),
                    ),

                    // Step 2 – Football Platform (all 14 games)
                    _stepCard(
                      context: context,
                      title: context.l10n.tr('auth_onboarding_step_platform_title'),
                      subtitle: context.l10n
                          .tr('auth_onboarding_step_platform_subtitle'),
                      active: _step >= 2,
                      content: _gamePicker(),
                    ),

                    // Step 3 – Experience Level
                    _stepCard(
                      context: context,
                      title: context.l10n.tr('auth_onboarding_step_experience_title'),
                      subtitle: context.l10n
                          .tr('auth_onboarding_step_experience_subtitle'),
                      active: _step >= 3,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(context.l10n.tr('auth_onboarding_experience_question')),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              context.l10n
                                  .tr('auth_onboarding_experience_beginner'),
                              context.l10n.tr(
                                  'auth_onboarding_experience_intermediate'),
                              context.l10n.tr(
                                  'auth_onboarding_experience_professional'),
                              context.l10n.tr(
                                  'auth_onboarding_experience_tournament_organizer'),
                            ]
                                .map(
                                  (lvl) => _choiceChip(
                                    label: lvl,
                                    groupValue: _experience,
                                    onSelected: (v) =>
                                        setState(() => _experience = v),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                    ),

                    // Step 4 – Goal
                    _stepCard(
                      context: context,
                      title: context.l10n.tr('auth_onboarding_step_goal_title'),
                      subtitle:
                          context.l10n.tr('auth_onboarding_step_goal_subtitle'),
                      active: _step >= lastStep,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(context.l10n.tr('auth_onboarding_goal_question')),
                          const SizedBox(height: 12),
                          TextField(
                            minLines: 3,
                            maxLines: 5,
                            decoration: InputDecoration(
                              labelText: context.l10n.tr('auth_onboarding_goal_label'),
                              hintText:
                                  context.l10n.tr('auth_onboarding_goal_hint'),
                            ),
                            onChanged: (v) => _goal = v.trim(),
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
      ),
    );
  }
}

// ─── Data model ──────────────────────────────────────────────────────────────

/// Immutable descriptor for a labelled group of games.
/// [label] holds an l10n key, resolved via `context.l10n.tr(...)` at
/// display time rather than a literal string.
class _GameGroup {
  const _GameGroup({
    required this.label,
    required this.icon,
    required this.games,
  });

  final String label;
  final IconData icon;
  final List<String> games;
}
