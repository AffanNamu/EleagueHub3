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
    };
  }

  Future<void> _finish() async {
    if (_saving) return;

    final teamName = _teamNameCtrl.text.trim();
    if (teamName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a team name.'),
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
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _choiceChip({
    required String label,
    required String groupValue,
    required ValueChanged<String> onSelected,
  }) {
    final brightness = Theme.of(context).brightness;
    final selected = groupValue == label;
    return ChoiceChip(
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
  }) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Step(
      title: Text(
        title,
        style: TextStyle(
          color: AppTheme.primaryText(brightness),
          fontWeight: FontWeight.w800,
        ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final canContinueStep0 = _teamNameCtrl.text.trim().isNotEmpty;
    final canContinueStep1 = _game.trim().isNotEmpty;
    final canContinueStep2 = _experience.trim().isNotEmpty;

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Onboarding'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.limeAccent,
                              foregroundColor: AppTheme.darkText,
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
                                : Text(_step == 3 ? 'Finish' : 'Continue'),
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
                      title: 'Team',
                      active: _step >= 0,
                      content: TextField(
                        controller: _teamNameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Team name',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    _stepCard(
                      context: context,
                      title: 'Game',
                      active: _step >= 1,
                      content: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _choiceChip(
                            label: 'eFootball',
                            groupValue: _game,
                            onSelected: (v) => setState(() => _game = v),
                          ),
                          _choiceChip(
                            label: 'FC Mobile',
                            groupValue: _game,
                            onSelected: (v) => setState(() => _game = v),
                          ),
                          _choiceChip(
                            label: 'PUBG',
                            groupValue: _game,
                            onSelected: (v) => setState(() => _game = v),
                          ),
                        ],
                      ),
                    ),
                    _stepCard(
                      context: context,
                      title: 'Experience',
                      active: _step >= 2,
                      content: Wrap(
                        spacing: 8,
                        runSpacing: 8,
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
                        ],
                      ),
                    ),
                    _stepCard(
                      context: context,
                      title: 'Goal',
                      active: _step >= 3,
                      content: TextField(
                        decoration: const InputDecoration(
                          labelText: 'What do you want to do?',
                        ),
                        onChanged: (v) => _goal = v.trim(),
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
