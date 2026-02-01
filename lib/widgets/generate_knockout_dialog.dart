import 'package:flutter/material.dart';

/// Returns a bool via Navigator.pop:
/// - true  => user confirmed "START KNOCKOUTS"
/// - false => user cancelled (or dismissed)
class GenerateKnockoutDialog extends StatelessWidget {
  final List<String> qualifiedTeams;

  const GenerateKnockoutDialog({super.key, required this.qualifiedTeams});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF000428),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      title: const Text(
        'Generate Knockout Bracket',
        style: TextStyle(color: Colors.white),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The following teams have qualified based on standings:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 15),
            Wrap(
              spacing: 8,
              children: qualifiedTeams
                  .map(
                    (t) => Chip(
                      label: Text(t, style: const TextStyle(fontSize: 10)),
                      backgroundColor: Colors.blueAccent.withOpacity(0.2),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'This will create the knockout matchups. This action cannot be undone.',
              style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          onPressed: () {
            // Let the caller trigger bracket generation based on the returned result.
            Navigator.pop(context, true);
          },
          child: const Text('START KNOCKOUTS'),
        ),
      ],
    );
  }
}
