import 'package:flutter/material.dart';

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
    final selected = groupValue == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canContinueStep0 = _teamNameCtrl.text.trim().isNotEmpty;
    final canContinueStep1 = _game.trim().isNotEmpty;
    final canContinueStep2 = _experience.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Onboarding'),
      ),
      body: SafeArea(
        child: Stepper(
          currentStep: _step,
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
          controlsBuilder: (context, details) {
            return Row(
              children: [
                FilledButton(
                  onPressed: _saving ? null : details.onStepContinue,
                  child: _saving && _step == 3
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_step == 3 ? 'Finish' : 'Continue'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _saving ? null : details.onStepCancel,
                  child: Text(_step == 0 ? 'Close' : 'Back'),
                ),
              ],
            );
          },
          steps: [
            Step(
              title: const Text('Team'),
              isActive: _step >= 0,
              content: TextField(
                controller: _teamNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Team name',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Step(
              title: const Text('Game'),
              isActive: _step >= 1,
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
            Step(
              title: const Text('Experience'),
              isActive: _step >= 2,
              content: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _choiceChip(
                    label: 'Beginner',
                    groupValue: _experience,
                    onSelected: (v) => setState(() => _experience = v),
                  ),
                  _choiceChip(
                    label: 'Intermediate',
                    groupValue: _experience,
                    onSelected: (v) => setState(() => _experience = v),
                  ),
                  _choiceChip(
                    label: 'Professional',
                    groupValue: _experience,
                    onSelected: (v) => setState(() => _experience = v),
                  ),
                ],
              ),
            ),
            Step(
              title: const Text('Goal'),
              isActive: _step >= 3,
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
    );
  }
}
