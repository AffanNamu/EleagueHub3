import 'package:flutter/material.dart';
import '../../../widgets/admin_score_card.dart';
import '../../logic/admin_service.dart';
import '../../../core/locale/app_localizations.dart';

class AdminScoreMgmtScreen extends StatelessWidget {
  const AdminScoreMgmtScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final adminService = AdminService();
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: const Color(0xFF4FC3F7),
      appBar: AppBar(title: Text(l10n.tr('admin_score_mgmt_appbar_title')), backgroundColor: Colors.transparent),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 5, // Replace with real match list from DB
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: AdminScoreCard(
              homeTeam: "${l10n.tr('admin_score_mgmt_team_fallback_prefix')} ${index + 1}",
              awayTeam: "${l10n.tr('admin_score_mgmt_team_fallback_prefix')} ${index + 2}",
              onSave: (hScore, aScore) async {
                await adminService.updateScore(index, hScore, aScore);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.tr('admin_score_mgmt_score_updated_success'))),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
