import 'package:flutter/material.dart';

import 'package:eleaguehub3/core/widgets/glass.dart';
import 'package:eleaguehub3/features/leagues/data/spaces_firebase.dart';

class LeagueSpaceCard extends StatelessWidget {
  final String leagueId;
  final LeagueSpacesFirebase _spaceRepo = LeagueSpacesFirebase();

  LeagueSpaceCard({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<dynamic>(
      stream: _spaceRepo.watchSpace(leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return SizedBox(
            height: 100,
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
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

        final liveDot = isLive ? cs.error : cs.onSurface.withOpacity(0.14);

        // Light theme: soften the live glow; dark theme: keep it slightly stronger.
        final glowOpacity = theme.brightness == Brightness.light ? 0.26 : 0.45;

        return Glass(
          borderRadius: 20,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Live Indicator
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: liveDot,
                  shape: BoxShape.circle,
                  boxShadow: isLive
                      ? [
                          BoxShadow(
                            color: cs.error.withOpacity(glowOpacity),
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
                        color: isLive ? cs.onSurface : cs.onSurface.withOpacity(0.45),
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      isLive ? 'Join the conversation now' : 'No active discussion',
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.65),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isLive)
                FilledButton(
                  onPressed: () {},
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('JOIN'),
                ),
            ],
          ),
        );
      },
    );
  }
}
