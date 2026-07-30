import 'package:cloud_firestore/cloud_firestore.dart';

import 'formation_detector.dart';
import 'formation_presets.dart';

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
    this.slotIndex = -1,
    this.photoUrl = '',
  });

  final String playerId;
  final String name;
  final String position;

  /// 0.0 (left/top) .. 1.0 (right/bottom), relative to pitch bounds.
  final double x;
  final double y;
  final bool isStarting;
  final int shirtNumber;

  /// Which formation-template slot (0-based, matches the order returned
  /// by FormationPresets.slotsFor(...)) this starter logically occupies.
  /// This is the STABLE identity used for rendering + editing — it must
  /// never be inferred from list position, since the players list is not
  /// guaranteed to be in template order (bench players are mixed in, and
  /// slots can be filled out of order). -1 means "bench" or "not yet
  /// assigned" (legacy data — auto-healed on load, see
  /// Squad._normalizeSlotIndexes).
  final int slotIndex;

  /// Cloudinary-hosted photo URL, resolved once via PlayerPhotoService
  /// when the player's real name matched a known player, then stored
  /// here permanently so no external API is ever called again for this
  /// player. Empty string means no photo (manual/unknown player name).
  final String photoUrl;

  factory SquadPlayerSlot.fromMap(Map<String, dynamic> map) {
    return SquadPlayerSlot(
      playerId: (map['playerId'] as String? ?? '').trim(),
      name: (map['name'] as String? ?? '').trim(),
      position: (map['position'] as String? ?? '').trim(),
      x: _asDouble(map['x']),
      y: _asDouble(map['y']),
      isStarting: map['isStarting'] == true,
      shirtNumber: _asInt(map['shirtNumber']),
      slotIndex: map.containsKey('slotIndex') ? _asInt(map['slotIndex']) : -1,
      photoUrl: (map['photoUrl'] as String? ?? '').trim(),
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
        'slotIndex': slotIndex,
        'photoUrl': photoUrl,
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
    final parsedPlayers = rawPlayers
        .whereType<Map>()
        .map((m) => SquadPlayerSlot.fromMap(m.cast<String, dynamic>()))
        .toList(growable: false);

    return Squad(
      gameId: doc.id,
      formation: (map['formation'] as String? ?? '4-3-3').trim(),
      players: _normalizeSlotIndexes(parsedPlayers),
      managerName: (map['managerName'] as String? ?? '').trim(),
      captainPlayerId: (map['captainPlayerId'] as String? ?? '').trim(),
      viceCaptainPlayerId: (map['viceCaptainPlayerId'] as String? ?? '').trim(),
      teamStrength: _asInt(map['teamStrength']),
      updatedAtMs: _asInt(map['updatedAtMs']),
    );
  }

  /// Self-heals squads saved before slotIndex existed (or that somehow
  /// ended up with two starters sharing the same slotIndex): any starting
  /// player missing a valid/unique slotIndex gets the next free index,
  /// in their existing list order. Runs on every load; a no-op once data
  /// is clean.
  static List<SquadPlayerSlot> _normalizeSlotIndexes(List<SquadPlayerSlot> players) {
    final startingCount = players.where((p) => p.isStarting).length;
    final validIndexes = <int>{
      for (final p in players)
        if (p.isStarting && p.slotIndex >= 0) p.slotIndex,
    };

    final isClean = validIndexes.length == startingCount;
    if (isClean) return players;

    final used = <int>{};
    int nextFree = 0;
    int pullNextFree() {
      while (used.contains(nextFree)) {
        nextFree++;
      }
      used.add(nextFree);
      return nextFree;
    }

    return players.map((p) {
      if (!p.isStarting) return p;
      final alreadyTaken = p.slotIndex >= 0 && !used.add(p.slotIndex);
      if (p.slotIndex >= 0 && !alreadyTaken) {
        return p;
      }
      final assigned = pullNextFree();
      return SquadPlayerSlot(
        playerId: p.playerId,
        name: p.name,
        position: p.position,
        x: p.x,
        y: p.y,
        isStarting: p.isStarting,
        shirtNumber: p.shirtNumber,
        slotIndex: assigned,
        photoUrl: p.photoUrl,
      );
    }).toList(growable: false);
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

  /// Returns a copy with [player] placed into the starting-XI TEMPLATE
  /// slot [slotIndex] (0-based, matching FormationPresets.slotsFor
  /// order). Any existing starter already occupying that slotIndex is
  /// replaced. [slotIndex] is force-applied onto [player] regardless of
  /// whatever slotIndex it already carried, so callers never need to set
  /// it themselves.
  Squad withStarterAtSlot(int slotIndex, SquadPlayerSlot player) {
    final normalizedPlayer = SquadPlayerSlot(
      playerId: player.playerId,
      name: player.name,
      position: player.position,
      x: player.x,
      y: player.y,
      isStarting: true,
      shirtNumber: player.shirtNumber,
      slotIndex: slotIndex,
      photoUrl: player.photoUrl,
    );

    final withoutThisSlot =
        players.where((p) => !(p.isStarting && p.slotIndex == slotIndex)).toList();

    return Squad(
      gameId: gameId,
      formation: formation,
      players: [...withoutThisSlot, normalizedPlayer],
      managerName: managerName,
      captainPlayerId: captainPlayerId,
      viceCaptainPlayerId: viceCaptainPlayerId,
      teamStrength: teamStrength,
      updatedAtMs: updatedAtMs,
    );
  }

  /// Removes whichever starting-XI player currently occupies template
  /// slot [slotIndex].
  Squad withStarterRemovedAtSlot(int slotIndex) {
    return Squad(
      gameId: gameId,
      formation: formation,
      players:
          players.where((p) => !(p.isStarting && p.slotIndex == slotIndex)).toList(growable: false),
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

  /// Free-drag repositioning: moves [playerId] to the given normalized
  /// pitch coordinates and re-detects the formation from the new shape.
  /// slotIndex (identity) and photoUrl are preserved — only the visual
  /// position moves.
  Squad withPlayerPosition(String playerId, double x, double y) {
    final nx = x.clamp(0.0, 1.0);
    final ny = y.clamp(0.0, 1.0);

    final updated = players.map((p) {
      if (p.playerId != playerId) return p;
      return SquadPlayerSlot(
        playerId: p.playerId,
        name: p.name,
        position: p.position,
        x: nx,
        y: ny,
        isStarting: p.isStarting,
        shirtNumber: p.shirtNumber,
        slotIndex: p.slotIndex,
        photoUrl: p.photoUrl,
      );
    }).toList(growable: false);

    final newStarters = updated.where((p) => p.isStarting).toList(growable: false);

    return Squad(
      gameId: gameId,
      formation: FormationDetector.detect(newStarters, fallback: formation),
      players: updated,
      managerName: managerName,
      captainPlayerId: captainPlayerId,
      viceCaptainPlayerId: viceCaptainPlayerId,
      teamStrength: teamStrength,
      updatedAtMs: updatedAtMs,
    );
  }

  /// Swaps the pitch POSITIONS (x/y only — not slotIndex identity) of two
  /// players, used when one is dragged and dropped on top of another,
  /// then re-detects the formation.
  Squad withPlayersSwapped(String playerIdA, String playerIdB) {
    if (playerIdA == playerIdB) return this;

    SquadPlayerSlot? a;
    SquadPlayerSlot? b;
    for (final p in players) {
      if (p.playerId == playerIdA) a = p;
      if (p.playerId == playerIdB) b = p;
    }
    if (a == null || b == null) return this;

    final aPos = a;
    final bPos = b;

    final updated = players.map((p) {
      if (p.playerId == playerIdA) {
        return SquadPlayerSlot(
          playerId: aPos.playerId,
          name: aPos.name,
          position: aPos.position,
          x: bPos.x,
          y: bPos.y,
          isStarting: aPos.isStarting,
          shirtNumber: aPos.shirtNumber,
          slotIndex: aPos.slotIndex,
          photoUrl: aPos.photoUrl,
        );
      }
      if (p.playerId == playerIdB) {
        return SquadPlayerSlot(
          playerId: bPos.playerId,
          name: bPos.name,
          position: bPos.position,
          x: aPos.x,
          y: aPos.y,
          isStarting: bPos.isStarting,
          shirtNumber: bPos.shirtNumber,
          slotIndex: bPos.slotIndex,
          photoUrl: bPos.photoUrl,
        );
      }
      return p;
    }).toList(growable: false);

    final newStarters = updated.where((p) => p.isStarting).toList(growable: false);

    return Squad(
      gameId: gameId,
      formation: FormationDetector.detect(newStarters, fallback: formation),
      players: updated,
      managerName: managerName,
      captainPlayerId: captainPlayerId,
      viceCaptainPlayerId: viceCaptainPlayerId,
      teamStrength: teamStrength,
      updatedAtMs: updatedAtMs,
    );
  }

  /// Snaps the current starting XI onto a known preset's template
  /// coordinates AND reassigns slotIndex to match that preset's order
  /// (used when the user taps a formation chip directly, rather than
  /// freely dragging). Starters are ordered by their current slotIndex
  /// first so the reassignment is stable and predictable.
  Squad withFormationApplied(String formationId) {
    final id = formationId.trim();
    final slots = FormationPresets.slotsFor(id);

    final starters = [...startingXI]
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));

    final updatedStarters = <SquadPlayerSlot>[];
    for (int i = 0; i < starters.length && i < slots.length; i++) {
      final s = starters[i];
      updatedStarters.add(SquadPlayerSlot(
        playerId: s.playerId,
        name: s.name,
        position: s.position,
        x: slots[i].x,
        y: slots[i].y,
        isStarting: true,
        shirtNumber: s.shirtNumber,
        slotIndex: i,
        photoUrl: s.photoUrl,
      ));
    }
    // Overflow (more starters than the new formation has slots for):
    // keep them as-is rather than dropping them, so no data is lost.
    for (int i = slots.length; i < starters.length; i++) {
      updatedStarters.add(starters[i]);
    }

    return Squad(
      gameId: gameId,
      formation: id,
      players: [...updatedStarters, ...bench],
      managerName: managerName,
      captainPlayerId: captainPlayerId,
      viceCaptainPlayerId: viceCaptainPlayerId,
      teamStrength: teamStrength,
      updatedAtMs: updatedAtMs,
    );
  }
}
