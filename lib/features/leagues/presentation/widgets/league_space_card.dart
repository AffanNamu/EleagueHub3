import 'package:flutter/material.dart';

import 'package:eleaguehub3/core/theme/app_theme.dart';
import 'package:eleaguehub3/core/widgets/glass.dart';
import 'package:eleaguehub3/features/leagues/data/spaces_firebase.dart';

class LeagueSpaceCard extends StatelessWidget {
  final String leagueId;
  final LeagueSpacesFirebase _spaceRepo = LeagueSpacesFirebase();

  LeagueSpaceCard({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return StreamBuilder<dynamic>(
      stream: _spaceRepo.watchSpace(leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 100,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.limeAccentDark,
              ),
            ),
          );
        }

        final space = snapshot.data;

        bool isLive = false;
        try {
          isLive = (space as dynamic)?.isLive == true;
        } catch (_) {
          isLive = false;
        }

        final liveDot = isLive
            ? Theme.of(context).colorScheme.error
            : AppTheme.secondaryText(brightness).withOpacity(0.30);

        final glowOpacity = theme.brightness == Brightness.light ? 0.20 : 0.40;

        return Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(16),
          fill: AppTheme.cardColor(brightness),
          borderColor: AppTheme.cardBorder(brightness),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: liveDot,
                  shape: BoxShape.circle,
                  boxShadow: isLive
                      ? [
                          BoxShadow(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withOpacity(glowOpacity),
                            blurRadius: 10,
                            spreadRadius: 1.5,
                          )
                        ]
                      : const [],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLive ? 'LIVE SPACE' : 'SPACE OFFLINE',
                      style: TextStyle(
                        color: isLive
                            ? AppTheme.primaryText(brightness)
                            : AppTheme.secondaryText(brightness),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      isLive
                          ? 'Join the conversation now'
                          : 'No active discussion',
                      style: TextStyle(
                        color: AppTheme.secondaryText(brightness),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLive)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.limeAccent,
                    foregroundColor: AppTheme.darkText,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {},
                  child: const Text('JOIN'),
                ),
            ],
          ),
        );
      },
    );
  }
}
