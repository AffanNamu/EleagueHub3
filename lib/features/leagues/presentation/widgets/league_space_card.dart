import 'package:flutter/material.dart';
import '../../models/league_space.dart';
import '../data/spaces_firebase.dart';
import '../../../core/widgets/glass.dart';

class LeagueSpaceCard extends StatelessWidget {
  final String leagueId;
  final LeagueSpacesFirebase _spaceRepo = LeagueSpacesFirebase();

  LeagueSpaceCard({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LeagueSpace?>(
      stream: _spaceRepo.watchSpace(leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }

        final space = snapshot.data;
        final bool isLive = space?.isLive ?? false;

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
                  color: isLive ? Colors.redAccent : Colors.white10,
                  shape: BoxShape.circle,
                  boxShadow: isLive ? [
                    BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)
                  ] : [],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLive ? "LIVE SPACE" : "SPACE OFFLINE",
                      style: TextStyle(
                        color: isLive ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      isLive ? "Join the conversation now" : "No active discussion",
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (isLive)
                ElevatedButton(
                  onPressed: () => /* Navigation to Space */ {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("JOIN"),
                ),
            ],
          ),
        );
      },
    );
  }
}
