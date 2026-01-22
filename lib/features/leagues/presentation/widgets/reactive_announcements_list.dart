import 'package:flutter/material.dart';
import '../../models/announcement.dart';
import '../data/announcements_firebase.dart';
import '../../../core/widgets/glass.dart';
import 'package:intl/intl.dart';

class ReactiveAnnouncementsList extends StatelessWidget {
  final String leagueId;
  final LeagueAnnouncementsFirebase _annRepo = LeagueAnnouncementsFirebase();

  ReactiveAnnouncementsList({super.key, required this.leagueId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<LeagueAnnouncement>>(
      stream: _annRepo.watchLeagueAnnouncements(leagueId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));
        }

        final announcements = snapshot.data ?? [];

        if (announcements.isEmpty) {
          return const Center(
            child: Text("No announcements yet", style: TextStyle(color: Colors.white38)),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: announcements.length,
          itemBuilder: (context, index) {
            final ann = announcements[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: Glass(
                borderRadius: 15,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          ann.title.toUpperCase(),
                          style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          DateFormat('HH:mm').format(ann.timestamp),
                          style: const TextStyle(color: Colors.white24, fontSize: 10),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ann.message,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
