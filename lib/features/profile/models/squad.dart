import 'package:cloud_firestore/cloud_firestore.dart';

/// A single player's placement in a squad. Positions are stored as
/// normalized coordinates (0.0–1.0) so the pitch is rendered fresh on
/// every device size — we never store rendered images.
class SquadPlayerSlot {
  const SquadPlayerSlot({
    required this.playerId,
    required this.name,
    required this.position, // e.g. "ST", "CB", "GK"
    required this.x,
    required this.y,
    required this.isStarting,
    required this.shirtNumber,
  });

  final String playerId;
  final String name;
  final String position;

  /// 0.0 (left/top) .. 1.0 (right/bottom), relative to pitch bounds.
  final double x;
  final double y;
  final bool isStarting;
  final int shirtNumber;

  factory SquadPlayerSlot.fromMap(Map<String, dynamic> map) {
    return SquadPlayerSlot(
      playerId: (map['playerId'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      position: (map['position'] as String? ?? '').trim(),
      x: _asDouble(map['x']),
      y: _asDouble(map['y']),
      isStarting: map['isStarting'] == true,
      shirtNumber: _asInt(map['shirtNumber']),
    );
  }

  Map<String, dynamic> toMap() => {
        'playerId': playerId,
        'name': name,
        'position': position,
        'x': x,
        'y': y,
        'isStarting': isStarting,
        'shirtNumber': shirtNumber,
      };

  static double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return 0.0;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }
}

/// One per game a user plays. Lives at users/{uid}/squads/{gameId}.
class Squad {
  const Squad({
    required this.gameId,
    required this.formation,
    required this.players,
    required this.managerName,
    required this.captainPlayerId,
    required this.viceCaptainPlayerId,
    required this.teamStrength,
    required this.updatedAtMs,
  });

  final String gameId;
  final String formation; // "4-3-3", "4-2-3-1", etc.
  final List<SquadPlayerSlot> players; // starting XI + bench, distinguished by isStarting
  final String managerName;
  final String captainPlayerId;
  final String viceCaptainPlayerId;
  final int teamStrength; // 0-100 overall rating
  final int updatedAtMs;

  List<SquadPlayerSlot> get startingXI =>
      players.where((p) => p.isStarting).toList(growable: false);

  List<SquadPlayerSlot> get bench =>
      players.where((p) => !p.isStarting).toList(growable: false);

  factory Squad.empty(String gameId) {
    return Squad(
      gameId: gameId,
      formation: '4-3-3',
      players: const [],
      managerName: '',
      captainPlayerId: '',
      viceCaptainPlayerId: '',
      teamStrength: 0,
      updatedAtMs: 0,
    );
  }

  factory Squad.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    final rawPlayers = (map['players'] as List?) ?? const [];
    return Squad(
      gameId: doc.id,
      formation: (map['formation'] as String? ?? '4-3-3').trim(),
      players: rawPlayers
          .whereType<Map>()
          .map((m) => SquadPlayerSlot.fromMap(m.cast<String, dynamic>()))
          .toList(growable: false),
      managerName: (map['managerName'] as String? ?? '').trim(),
      captainPlayerId: (map['captainPlayerId'] as String? ?? '').trim(),
      viceCaptainPlayerId: (map['viceCaptainPlayerId'] as String? ?? '').trim(),
      teamStrength: _asInt(map['teamStrength']),
      updatedAtMs: _asInt(map['updatedAtMs']),
    );
  }

  Map<String, dynamic> toMap() => {
        'formation': formation,
        'players': players.map((p) => p.toMap()).toList(growable: false),
        'managerName': managerName.trim(),
        'captainPlayerId': captainPlayerId.trim(),
        'viceCaptainPlayerId': viceCaptainPlayerId.trim(),
        'teamStrength': teamStrength.clamp(0, 100),
        'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
      };

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 0;
  }

  /// Returns a copy with [player] placed into the starting-XI position
  /// at [slotIndex] (0-based, matching FormationPresets.slotsFor order).
  /// Any existing starter at that index is replaced.
  Squad withStarterAtSlot(int slotIndex, SquadPlayerSlot player) {
    final starters = [...startingXI];
    while (starters.length <= slotIndex) {
      starters.add(const SquadPlayerSlot(
        playerId: '',
        name: '',
        position: '',
        x: 0,
        y: 0,
        isStarting: true,
        shirtNumber: 0,
      ));
    }
    starters[slotIndex] = player;

    final cleanedStarters =
        starters.where((p) => p.name.trim().isNotEmpty).toList(growable: false);

    return Squad(
      gameId: gameId,
      formation: formation,
      players: [...cleanedStarters, ...bench],
      managerName: managerName,
      captainPlayerId: captainPlayerId,
      viceCaptainPlayerId: viceCaptainPlayerId,
      teamStrength: teamStrength,
      updatedAtMs: updatedAtMs,
    );
  }

  /// Removes whichever starting-XI player currently occupies [slotIndex].
  Squad withStarterRemovedAtSlot(int slotIndex) {
    final starters = [...startingXI];
    if (slotIndex < 0 || slotIndex >= starters.length) return this;
    starters.removeAt(slotIndex);

    return Squad(
      gameId: gameId,
      formation: formation,
      players: [...starters, ...bench],
      managerName: managerName,
      captainPlayerId: captainPlayerId,
      viceCaptainPlayerId: viceCaptainPlayerId,
      teamStrength: teamStrength,
      updatedAtMs: updatedAtMs,
    );
  }

  Squad withBenchPlayerAdded(SquadPlayerSlot player) {
    return Squad(
      gameId: gameId,
      formation: formation,
      players: [...players, player],
      managerName: managerName,
      captainPlayerId: captainPlayerId,
      viceCaptainPlayerId: viceCaptainPlayerId,
      teamStrength: teamStrength,
      updatedAtMs: updatedAtMs,
    );
  }

  Squad withPlayerRemoved(String playerId) {
    return Squad(
      gameId: gameId,
      formation: formation,
      players: players.where((p) => p.playerId != playerId).toList(growable: false),
      managerName: managerName,
      captainPlayerId: captainPlayerId == playerId ? '' : captainPlayerId,
      viceCaptainPlayerId: viceCaptainPlayerId == playerId ? '' : viceCaptainPlayerId,
      teamStrength: teamStrength,
      updatedAtMs: updatedAtMs,
    );
  }

  Squad withCaptain(String playerId) {
    return Squad(
      gameId: gameId,
      formation: formation,
      players: players,
      managerName: managerName,
      captainPlayerId: playerId,
      viceCaptainPlayerId: viceCaptainPlayerId == playerId ? '' : viceCaptainPlayerId,
      teamStrength: teamStrength,
      updatedAtMs: updatedAtMs,
    );
  }

  Squad withViceCaptain(String playerId) {
    return Squad(
      gameId: gameId,
      formation: formation,
      players: players,
      managerName: managerName,
      captainPlayerId: captainPlayerId == playerId ? '' : captainPlayerId,
      viceCaptainPlayerId: playerId,
      teamStrength: teamStrength,
      updatedAtMs: updatedAtMs,
    );
  }
}
