import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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
      label: '⚽ Console / PC',
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
      label: '📱 Mobile',
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
            ? 'Must be ${UsernameUtils.minLength}-'
                '${UsernameUtils.maxLength} characters.'
            : 'Lowercase letters, numbers, and underscores only.';
      });
      return;
    }

    if (UsernameUtils.isReserved(raw)) {
      setState(() {
        _usernameStatus = _UsernameFieldStatus.invalid;
        _usernameError = 'That username is reserved.';
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
        _usernameError = available ? null : 'That username is taken.';
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
          _imageError = pickResult.errorMessage ?? 'Could not pick image.';
        });
        return;
      }

      final picked = pickResult.file!;

      if (picked.size > _maxImageBytes) {
        setState(() {
          _imageError =
              'Image too large. Please select an image under 5 MB.';
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
      setState(() => _imageError = e.message ?? 'Could not pick image.');
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
      _snack('Please enter your club or gamer name.');
      return;
    }

    if (!_usernameIsReady) {
      _snack('Please choose an available username.');
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
        _sectionTitle('Select Your Main Football Game'),
        ..._gameGroups.map((group) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _groupHeader(group.label, group.icon),
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
        _sectionTitle('Username'),
        const SizedBox(height: 4),
        Text(
          'This is how other players find and mention you. '
          'Required, and it can\'t be changed by anyone else once it\'s yours.',
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
            labelText: 'Choose a username',
            hintText: 'Example: galaxy_fc',
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
        _sectionTitle('Profile / Team Photo'),
        const SizedBox(height: 4),
        Text(
          'This also becomes your team\'s identity image around '
          'eSportlyic. Optional — you can add or change it later from '
          'your profile.',
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
                  child: const Text('Remove photo'),
                )
              else
                Text(
                  'Tap to add a photo, or skip this step.',
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
      appBar: AppBar(title: const Text('Welcome to eSportlyic')),
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
                                        ? 'Complete Setup'
                                        : (_step == 1 &&
                                                _uploadedImageUrl == null
                                            ? 'Skip'
                                            : 'Continue'),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: _saving ? null : details.onStepCancel,
                            child:
                                Text(_step == 0 ? 'Close' : 'Back'),
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
                      title: 'Identity',
                      subtitle:
                          'Create your football gaming identity on eSportlyic.',
                      active: _step >= 0,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Club / Gamer Name'),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _teamNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Enter your club or gamer name',
                              hintText: 'Example: Galaxy FC',
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
                      title: 'Profile Photo',
                      subtitle: 'Optional — add it now or later.',
                      active: _step >= 1,
                      content: _imageStep(),
                    ),

                    // Step 2 – Football Platform (all 14 games)
                    _stepCard(
                      context: context,
                      title: 'Football Platform',
                      subtitle:
                          'Choose the football game you mainly compete in.',
                      active: _step >= 2,
                      content: _gamePicker(),
                    ),

                    // Step 3 – Experience Level
                    _stepCard(
                      context: context,
                      title: 'Experience Level',
                      subtitle:
                          'Help us personalize tournaments and matchmaking.',
                      active: _step >= 3,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('How Experienced Are You?'),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              'Beginner',
                              'Intermediate',
                              'Professional',
                              'Tournament Organizer',
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
                      title: 'Your Goal',
                      subtitle:
                          'Tell us what you want to achieve on eSportlyic.',
                      active: _step >= lastStep,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('What Brings You Here?'),
                          const SizedBox(height: 12),
                          TextField(
                            minLines: 3,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              labelText: 'Your goal',
                              hintText:
                                  'Example: Compete in tournaments, grow my club, organize leagues, stream matches...',
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
