import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class MyFixturesFilter extends StatefulWidget {
  final Function(bool) onToggle;

  const MyFixturesFilter({super.key, required this.onToggle});

  @override
  State<MyFixturesFilter> createState() => _MyFixturesFilterState();
}

class _MyFixturesFilterState extends State<MyFixturesFilter> {
  bool isMyMatches = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: GestureDetector(
        onTap: () {
          setState(() => isMyMatches = !isMyMatches);
          widget.onToggle(isMyMatches);
        },
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: AppTheme.cardColor(brightness),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.cardBorder(brightness)),
            boxShadow: AppTheme.softCardShadow(brightness),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: isMyMatches
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: (MediaQuery.of(context).size.width - 48) / 2,
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.limeAccent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Text(
                        'All Matches',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: isMyMatches
                              ? AppTheme.secondaryText(brightness)
                              : AppTheme.darkText,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'My Matches',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: isMyMatches
                              ? AppTheme.darkText
                              : AppTheme.secondaryText(brightness),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
