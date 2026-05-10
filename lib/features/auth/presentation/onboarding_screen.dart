import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/glass.dart';
import '../../../core/widgets/glass_scaffold.dart';
import '../data/user_profile_repository.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final UserProfileRepository _profiles = UserProfileRepository();

  final TextEditingController _teamNameCtrl = TextEditingController();

  bool _saving = false;
  int _step = 0;

  String _game = '';
  String _experience = '';
  String _goal = '';

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildOnboardingAnswers() {
    return <String, dynamic>{
      'game': _game,
      'experience': _experience,
      'goal': _goal,
      'category': 'football',
    };
  }

  Future<void> _finish() async {
    if (_saving) return;

    final teamName = _teamNameCtrl.text.trim();
    if (teamName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your club or gamer name.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final onboardingAnswers = _buildOnboardingAnswers();

      await _profiles.createProfileIfMissing(
        teamName: teamName,
        authProvider: 'email',
        onboardingAnswers: onboardingAnswers,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

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
    final theme = Theme.of(context);
    final brightness = theme.brightness;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final canContinueStep0 = _teamNameCtrl.text.trim().isNotEmpty;
    final canContinueStep1 = _game.trim().isNotEmpty;
    final canContinueStep2 = _experience.trim().isNotEmpty;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Welcome to eSportlyic'),
      ),
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
                            onPressed: _saving ? null : details.onStepContinue,
                            child: _saving && _step == 3
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.darkText,
                                    ),
                                  )
                                : Text(
                                    _step == 3 ? 'Complete Setup' : 'Continue',
                                  ),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: _saving ? null : details.onStepCancel,
                            child: Text(_step == 0 ? 'Close' : 'Back'),
                          ),
                        ],
                      ),
                    );
                  },
                  onStepContinue: () {
                    if (_step == 0 && canContinueStep0) {
                      setState(() => _step = 1);
                      return;
                    }

                    if (_step == 1 && canContinueStep1) {
                      setState(() => _step = 2);
                      return;
                    }

                    if (_step == 2 && canContinueStep2) {
                      setState(() => _step = 3);
                      return;
                    }

                    if (_step == 3) {
                      _finish();
                    }
                  },
                  onStepCancel: () {
                    if (_step == 0) {
                      Navigator.of(context).maybePop();
                      return;
                    }

                    setState(() => _step -= 1);
                  },
                  steps: [
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
                        ],
                      ),
                    ),
                    _stepCard(
                      context: context,
                      title: 'Football Platform',
                      subtitle:
                          'Choose the football game you mainly compete in.',
                      active: _step >= 1,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Select Your Main Football Game'),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _choiceChip(
                                label: 'eFootball Mobile',
                                icon: Icons.sports_soccer,
                                groupValue: _game,
                                onSelected: (v) =>
                                    setState(() => _game = v),
                              ),
                              _choiceChip(
                                label: 'EA SPORTS FC Mobile',
                                icon: Icons.sports_soccer,
                                groupValue: _game,
                                onSelected: (v) =>
                                    setState(() => _game = v),
                              ),
                              _choiceChip(
                                label: 'eFootball Console',
                                icon: Icons.sports_esports,
                                groupValue: _game,
                                onSelected: (v) =>
                                    setState(() => _game = v),
                              ),
                              _choiceChip(
                                label: 'EA SPORTS FC Console',
                                icon: Icons.sports_esports,
                                groupValue: _game,
                                onSelected: (v) =>
                                    setState(() => _game = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _stepCard(
                      context: context,
                      title: 'Experience Level',
                      subtitle:
                          'Help us personalize tournaments and matchmaking.',
                      active: _step >= 2,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('How Experienced Are You?'),
                          const SizedBox(height: 14),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _choiceChip(
                                label: 'Beginner',
                                groupValue: _experience,
                                onSelected: (v) =>
                                    setState(() => _experience = v),
                              ),
                              _choiceChip(
                                label: 'Intermediate',
                                groupValue: _experience,
                                onSelected: (v) =>
                                    setState(() => _experience = v),
                              ),
                              _choiceChip(
                                label: 'Professional',
                                groupValue: _experience,
                                onSelected: (v) =>
                                    setState(() => _experience = v),
                              ),
                              _choiceChip(
                                label: 'Tournament Organizer',
                                groupValue: _experience,
                                onSelected: (v) =>
                                    setState(() => _experience = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _stepCard(
                      context: context,
                      title: 'Your Goal',
                      subtitle:
                          'Tell us what you want to achieve on eSportyic.',
                      active: _step >= 3,
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
