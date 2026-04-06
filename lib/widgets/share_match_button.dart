import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme/app_theme.dart';
import '../features/leagues/logic/match_sheet_service.dart';

class ShareMatchButton extends StatelessWidget {
  final String leagueName;
  final String homeTeam;
  final String awayTeam;
  final int homeScore;
  final int awayScore;

  const ShareMatchButton({
    super.key,
    required this.leagueName,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeScore,
    required this.awayScore,
  });

  void _handleShare(BuildContext context) {
    final report = MatchSheetService.generateTextReport(
      leagueName: leagueName,
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      homeScore: homeScore,
      awayScore: awayScore,
    );

    Share.share(report, subject: 'Match Result: $homeTeam vs $awayTeam');
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _handleShare(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.limeAccent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: AppTheme.fabGlow(Theme.of(context).brightness),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.share, color: AppTheme.darkText),
            SizedBox(width: 10),
            Text(
              'SHARE MATCH',
              style: TextStyle(
                color: AppTheme.darkText,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
