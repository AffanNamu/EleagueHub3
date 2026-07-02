# 🌍 eSportLytic: World Cup Tournament Engine & Architecture Master Documentation
**Version:** 1.0.0 (Production Release)  
**Target Audience:** Backend Engineers, Flutter Developers, QA Automation, System Architects  
**Purpose:** Comprehensive technical breakdown of the FIFA 2022 (32-Team) and FIFA 2026 (48-Team) World Cup implementation. This document is designed so that *any* developer picking up this codebase can understand the data flow, engine logic, UI integration, and how to debug/fix edge cases without breaking existing Classic, UCL Group, or UCL Swiss formats.

---

## 📑 TABLE OF CONTENTS
1. [Executive Summary & Feature Scope](#1-executive-summary--feature-scope)
2. [System Architecture & Data Flow](#2-system-architecture--data-flow)
3. [Domain Models & Enum Contracts](#3-domain-models--enum-contracts)
4. [The Tournament Engine (Core Logic)](#4-the-tournament-engine-core-logic)
   - 4.1 Group Stage Fixture Generation
   - 4.2 Standings & FIFA Tie-Breakers
   - 4.3 Qualification & Knockout Seeding (32 vs 48)
   - 4.4 Knockout Tree Building & Match Advancement
5. [UI/UX Implementation & State Management](#5-uiux-implementation--state-management)
6. [Firestore Schema & Backward Compatibility](#6-firestore-schema--backward-compatibility)
7. [Edge Cases, Pitfalls & Troubleshooting Guide](#7-edge-cases-pitfalls--troubleshooting-guide)
8. [File-by-File Reference Map](#8-file-by-file-reference-map)
9. [Testing & QA Checklist](#9-testing--qa-checklist)

---

## 1. Executive Summary & Feature Scope

The **World Cup** feature introduces a completely isolated, premium tournament engine to the `eSportLytic` platform. Unlike existing formats (Classic, UCL Group, UCL Swiss), the World Cup engine supports:
1. **FIFA 2022 Format (32 Teams):** 8 Groups of 4. Single round-robin group stage. Top 2 advance to Round of 16 (R16).
2. **FIFA 2026 Format (48 Teams):** 12 Groups of 4. Single round-robin group stage. Top 2 + 8 Best 3rd-placed teams advance to Round of 32 (R32).
3. **Automatic Bracket Generation:** Zero manual scheduling. The engine automatically wires `nextMatchId` and `loserGoesToMatchId` (for Semi-Final losers to the 3rd Place match).
4. **FIFA-Compliant Tie-Breakers:** Head-to-Head (H2H) cluster resolution for teams tied on Points, Goal Difference (GD), and Goals For (GF).

**CRITICAL RULE:** The World Cup engine *never* mutates or interferes with existing `LeagueFormat.classic`, `LeagueFormat.uclGroup`, or `LeagueFormat.uclSwiss` logic. All new logic is gated behind `LeagueFormat.worldCup`.

---

## 2. System Architecture & Data Flow

### 2.1 High-Level Flow
```text
[User UI] -> [League Creation Wizard] -> [Firestore Write]
      |
      v
[Add Teams Screen] -> [Auto-Assign Groups A-L] -> [Local Repo Save]
      |
      v
[Group Draw Screen] -> [Fixture Generator (Single RR)] -> [Firestore Write]
      |
      v
[Admin Score Mgmt] -> [Update Scores] -> [Standings Calculator] -> [Auto-Update Team Aggregates]
      |
      v
[Generate Knockouts] -> [Tournament Controller (Seeding)] -> [Bracket Tree Wiring]
      |
      v
[Knockout Score Mgmt] -> [Process Match Result] -> [Advance Winner / Route Loser]
```

### 2.2 Repository Pattern
The app uses a dual-repository pattern for offline-first resilience:
*   `LocalLeaguesRepository`: Handles local caching, UI state, and acts as the primary reader for screens.
*   `LeaguesRepositoryFirebase`: Handles authoritative Firestore writes, security rule compliance, and batch operations.

**World Cup Specifics:** The `LocalLeaguesRepository` now recognizes `LeagueFormat.worldCup` to enable group-based filtering in the Fixtures and Admin Score screens. The `roundOrder` sorting array has been updated to include `'Round of 32'`.

---

## 3. Domain Models & Enum Contracts

### 3.1 `LeagueFormat` (Enum)
```dart
enum LeagueFormat {
  classic,    // index 0
  uclGroup,   // index 1
  uclSwiss,   // index 2
  worldCup,   // index 3 (NEW)
}
```
*Warning:* Do NOT reorder these. The `index` is serialized to Firestore. `fromInt()` safely defaults to `classic` for unknown indices to prevent legacy data corruption.

### 3.2 `WorldCupFormat` (Enum)
Stored inside `LeagueSettings.worldCupFormat`.
```dart
enum WorldCupFormat {
  fifa2022, // 32 Teams, 8 Groups
  fifa2026, // 48 Teams, 12 Groups
}
```
**Properties:**
*   `teamCount`: Returns 32 or 48.
*   `groupCount`: Returns 8 or 12.
*   `teamsPerGroup`: Always 4.
*   `firestoreKey`: `'fifa2022'` or `'fifa2026'` (Used for safe string serialization).

### 3.3 `WorldCupQualificationSlot` (Enum)
Used internally by the seeding algorithm to track *how* a team qualified, ensuring correct bracket placement.
```dart
enum WorldCupQualificationSlot {
  groupWinner,   // Finished 1st
  groupRunnerUp, // Finished 2nd
  bestThird,     // Finished 3rd, but ranked in top 8 across all groups (48-team only)
}
```

### 3.4 `LeagueSettings` (Model)
```dart
class LeagueSettings {
  final bool doubleRoundRobin;
  final int groupSize;
  final int swissRounds;
  final int lastPulledAtMs;
  final WorldCupFormat worldCupFormat; // NEW
}
```
*Design Decision:* `worldCupFormat` is stored in `Settings` rather than the root `League` model to maintain a clean separation of structural rules vs. metadata. It defaults to `fifa2022` during deserialization for backward compatibility.

---

## 4. The Tournament Engine (Core Logic)

This is the most critical section. If you are debugging bracket issues, qualification errors, or tie-breaker anomalies, start here.

### 4.1 Group Stage Fixture Generation
**File:** `lib/features/leagues/logic/fixture_generator.dart`
**Method:** `generateWorldCupGroupStage()`

**Algorithm:**
1. Validates that `teams.length` exactly matches `worldCupFormat.teamCount` (32 or 48).
2. Validates that every team has a `groupId` assigned (e.g., `'Group A'` through `'Group L'`).
3. Validates that the number of unique `groupId`s matches `worldCupFormat.groupCount`.
4. Validates that every group contains exactly 4 teams.
5. Iterates through each group and calls `RoundRobinGenerator.generate(doubleRoundRobin: false)`.
   * *Note:* World Cup groups are **always single round-robin** (3 matches per team, 6 matches per group). The engine forces `doubleRoundRobin = false` regardless of league settings.

**Edge Case Handling:** If a group has 3 teams or 5 teams, the method returns an empty list and triggers an assertion failure in debug mode. The UI catches this and shows a "Complete group draw first" toast.

### 4.2 Standings & FIFA Tie-Breakers
**File:** `lib/features/leagues/domain/standings/standings_calculator.dart`

The `StandingsCalculator` computes the group tables. For the World Cup, we pass `fifaGroupTieBreakers: true`.

**Sorting Priority:**
1. `finalPoints` DESC (Base Points + Admin Adjustments)
2. `goalDifference` DESC
3. `goalsFor` DESC
4. **FIFA Head-to-Head (H2H) Cluster Resolution** (NEW)
5. `teamId` ASC (Deterministic fallback)

#### How H2H Cluster Resolution Works
If Team A, Team B, and Team C are tied on Points, GD, and GF:
1. The calculator isolates these three teams into a "cluster".
2. It filters the `matches` list to **only** include matches played *between* A, B, and C.
3. It recalculates a mini-table for just these three teams based on H2H Points, H2H GD, and H2H GF.
4. It re-sorts the cluster based on this mini-table.
5. Teams outside the cluster are unaffected.

*Code Snippet (Internal Logic):*
```dart
static List<StandingsRow> _resolveClusterByHeadToHead({
  required List<StandingsRow> cluster,
  required List<FixtureMatch> matches,
}) {
  final ids = cluster.map((e) => e.teamId).toSet();
  // ... builds _H2HStats map ...
  // ... filters matches where homeId and awayId are BOTH in ids ...
  // ... sorts cluster by H2H points -> H2H GD -> H2H GF -> teamId ...
}
```

### 4.3 Qualification & Knockout Seeding
**File:** `lib/features/leagues/domain/logic/tournament_controller.dart`

#### 4.3.1 FIFA 2022 (32 Teams) -> `seedWorldCupKnockouts32()`
*   **Qualification:** Top 2 from 8 groups (16 teams).
*   **Bracket:** Round of 16 -> QF -> SF -> 3rd Place & Final.
*   **Pairing Logic (Official FIFA):**
    *   Match 1: 1A vs 2B
    *   Match 2: 1C vs 2D
    *   Match 3: 1B vs 2A
    *   Match 4: 1D vs 2C
    *   Match 5: 1E vs 2F
    *   Match 6: 1G vs 2H
    *   Match 7: 1F vs 2E
    *   Match 8: 1H vs 2G
*   *Implementation:* Uses a hardcoded `_WcPairing` array to map `groupStandings` keys (sorted A-H) to the correct R16 slots. This ensures the bracket halves are correctly separated (e.g., A/B/C/D do not meet E/F/G/H until the Final).

#### 4.3.2 FIFA 2026 (48 Teams) -> `seedWorldCupKnockouts48()`
*   **Qualification:** Top 2 from 12 groups (24 teams) + 8 Best 3rd-placed teams.
*   **Best 3rd Calculation:** All 12 third-placed teams are sorted by Points -> GD -> GF -> teamId. The top 8 advance.
*   **Bracket:** Round of 32 -> R16 -> QF -> SF -> 3rd Place & Final.
*   **Pairing Logic (R32):**
    *   *Slots 0-7:* Winners of Groups A-H vs the 8 Best 3rd-Placed Teams (ranked 1-8).
    *   *Slots 8-11:* Runners-up of Groups A-H paired adjacently (2A vs 2B, 2C vs 2D, 2E vs 2F, 2G vs 2H).
    *   *Slots 12-15:* Cross-paired Groups I-L (1I vs 2J, 1K vs 2L, 1J vs 2I, 1L vs 2K).

*Developer Warning:* The 48-team seeding relies heavily on array indexing (`sublist(8, 12)` for Groups I-L). If the `groupStandings` map keys are not sorted alphabetically (A, B, C... L), the seeding will break. The engine enforces `keys.toList()..sort()` before seeding.

### 4.4 Knockout Tree Building & Match Advancement
**Method:** `_buildKnockoutTree()`

This method generates the skeleton of `KnockoutMatch` objects.
1.  **Skeleton Generation:** Creates matches for the starting round (R16 or R32), then iteratively halves the match count, assigning `roundName` (e.g., `'Quarter Finals'`) until `matchCount == 1` (Final).
2.  **Wiring `nextMatchId`:** Iterates through the rounds. For every match in Round N, it calculates the target match in Round N+1 using `nextIndex = j ~/ 2`.
3.  **3rd Place Match Routing:** If `includeThirdPlace == true`, it creates a `'3rd Place'` match. It then finds the two Semi-Final matches and sets their `loserGoesToMatchId` to the 3rd Place match ID.

**Match Advancement (`processMatchResult`):**
When an admin updates a knockout score:
1.  Determines the winner (or prompts for `tiebreakWinnerTeamId` if drawn).
2.  Finds the `nextMatchId`.
3.  Determines if the winner goes into the `homeTeamId` or `awayTeamId` slot of the next match based on the feeder match index (`_slotForAdvancement`).
4.  If the match was a Semi-Final, routes the `loserId` to the `loserGoesToMatchId` (3rd Place match).

---

## 5. UI/UX Implementation & State Management

### 5.1 Creation Flow
**Files:** `league_creation_dashboard.dart`, `league_create_wizard.dart`
*   **Dashboard:** Features a premium "World Cup" card with a gold gradient. Selecting it reveals a sub-selector for FIFA 2022 vs 2026.
*   **Wizard:** Adds a "World Cup" `ChoiceChip`. When selected, `_maxTeams` dynamically locks to `worldCupFormat.teamCount`. `_supportsHomeAwayMatches` returns `false`, hiding the Home/Away toggle.
*   **State:** The selected `WorldCupFormat` is passed into `LeagueSettings` during the Firestore write.

### 5.2 Team Management & Group Draw
**Files:** `add_teams_screen.dart`, `group_draw_screen.dart`
*   **Add Teams:** Recognizes `worldCup` as a grouped format. It does *not* show the manual group selector (Groups A-L) because World Cup groups are auto-assigned to ensure perfect 4-team distribution.
*   **Group Draw:**
    *   Loads teams and checks `_isGroupedFormat` (now includes `worldCup`).
    *   Generates group names dynamically: `_allGroupNamesAtoL.take(fmt.groupCount)`.
    *   Provides a "Start Draw" animation that assigns `groupId` to teams.
    *   "Generate Fixtures" button calls `FixtureGenerator.generateWorldCupGroupStage()`.

### 5.3 Fixtures & Score Management
**Files:** `fixtures_screen.dart`, `admin_score_mgmt_screen.dart`
*   **Group Filtering:** Both screens now use `bool get _isGroupedFormat => _format == LeagueFormat.uclGroup || _format == LeagueFormat.worldCup;`. This enables the horizontal group selector (Group A, Group B... Group L).
*   **Round Filtering:** Correctly calculates `totalRounds` based on the selected group. (World Cup groups have exactly 3 rounds).
*   **Score Entry Tile:** Displays the `groupLabel` (e.g., "Group C") at the top of the match card if it's a grouped format.

### 5.4 Knockout Bracket Display
**Files:** `knockout_bracket_screen.dart`, `admin_knockout_score_mgmt_screen.dart`
*   **Round Order:** Both files maintain a `_roundOrder` list. This list **must** include `'Round of 32'` before `'Round of 16'`.
    ```dart
    static const _roundOrder = <String>[
      'Play-off',
      'Round of 32', // CRITICAL FOR 48-TEAM
      'Round of 16',
      'Quarter Finals',
      'Semi Finals',
      'Final',
      '3rd Place',
    ];
    ```
*   **Bracket Painter:** The `BracketPainter` uses mathematical offsets (`_centerY`) based on the `maxMatches` in the first round. For a 48-team tournament, the first round has 16 matches (R32). The painter automatically scales the vertical spacing to accommodate 16 matches on the left/right pillars.

---

## 6. Firestore Schema & Backward Compatibility

### 6.1 League Document Structure
```json
{
  "id": "mlc_master123_1",
  "name": "Global World Cup 2026",
  "format": 3, // LeagueFormat.worldCup.index
  "maxTeams": 48,
  "settings": {
    "doubleRoundRobin": false,
    "groupSize": 4,
    "swissRounds": 8,
    "lastPulledAtMs": 0,
    "worldCupFormat": "fifa2026" // NEW STRING KEY
  },
  "organizerUid": "abc123...",
  "memberIds": ["abc123...", "def456..."]
}
```

### 6.2 Backward Compatibility Strategy
*   **Old Leagues:** Existing leagues have `format: 0, 1, or 2`. The `settings` map may lack `worldCupFormat`.
*   **Deserialization Safety:**
    ```dart
    // In LeagueSettings.fromMap()
    worldCupFormat: WorldCupFormatX.fromString(
      map['worldCupFormat'] as String?, // Returns fifa2022 if null
    ),
    ```
*   **Migration:** **NO MIGRATION IS REQUIRED.** The engine gracefully handles missing `worldCupFormat` keys by defaulting to `fifa2022`, which is safely ignored by non-World Cup leagues.

### 6.3 Security Rules Implications
The `updateMatchScoreAndUpdateTeamAggregates` method uses a Firestore Transaction.
*   **Rule:** `allow update: if request.auth.uid == resource.data.organizerUid;`
*   **World Cup Context:** The transaction reads the `teams` subcollection to update `basePoints`, `goalDifference`, etc. Because World Cup teams are stored in the exact same `teams` subcollection format as Classic/UCL leagues, **no security rule changes are required.**

---

## 7. Edge Cases, Pitfalls & Troubleshooting Guide

This section is your "Bug Fixer" matrix. If a user reports a bug, find the symptom here.

### Symptom 1: "The Round of 32 bracket is displaying out of order / overlapping."
*   **Root Cause:** The `_roundOrder` array in `knockout_bracket_screen.dart` or `admin_knockout_score_mgmt_screen.dart` is missing `'Round of 32'`, or it's placed *after* `'Round of 16'`.
*   **Fix:** Ensure `'Round of 32'` is at index 1 (after `'Play-off'`). The `BracketPainter` relies on the `maxMatches` of the *first* round to calculate vertical spacing. If R32 is missing, it thinks R16 (8 matches) is the first round, causing massive vertical overlap.

### Symptom 2: "Teams are advancing to the wrong side of the bracket."
*   **Root Cause:** The `groupStandings` map keys were not sorted alphabetically before seeding.
*   **Fix:** In `TournamentController.seedWorldCupKnockouts32/48`, verify this line exists:
    `final keys = groupStandings.keys.toList()..sort();`
    If Group C is processed before Group A, the `_WcPairing` array will map 1C to the 1A slot, destroying the bracket halves.

### Symptom 3: "Three teams are tied on 4 points, 0 GD, 3 GF. The standings are random."
*   **Root Cause:** The `fifaGroupTieBreakers` flag was not passed to the `StandingsCalculator`.
*   **Fix:** Ensure the caller (e.g., `league_standings_screen.dart` or the qualification engine) passes `fifaGroupTieBreakers: true` when calculating World Cup group tables. Without it, the engine falls back to `teamId ASC`, which looks random to users.

### Symptom 4: "I can't generate World Cup fixtures. It says 'Invalid group structure'."
*   **Root Cause:** The `Team.groupId` field is null or empty for some teams, or a group has 3 teams instead of 4.
*   **Fix:** The `generateWorldCupGroupStage` method strictly enforces `teams.length == 32/48` and `group.length == 4`. If the user manually added teams via CSV and missed the group assignment, the auto-assigner in `add_teams_screen.dart` (`_autoAssignWorldCupGroups`) must be triggered. Check if the UI correctly routes to the Group Draw screen before allowing fixture generation.

### Symptom 5: "The Semi-Final loser didn't go to the 3rd Place match."
*   **Root Cause:** The `loserGoesToMatchId` was not wired during tree generation.
*   **Fix:** Check `_buildKnockoutTree()`. Ensure `includeThirdPlace: true` is passed when calling it for World Cup formats. The code iterates through the `'Semi Finals'` list and sets `loserGoesToMatchId` on *both* SF matches. If one is missing, the routing fails.

### Symptom 6: "Best 3rd place teams are not qualifying correctly in 48-team."
*   **Root Cause:** The sorting logic for 3rd place teams is ignoring `adminAdjustment`.
*   **Fix:** In `seedWorldCupKnockouts48`, the code sorts `allThirdPlaced` using `b.finalPoints.compareTo(a.finalPoints)`. `finalPoints` includes `adminAdjustment`. If an admin penalized a team, they correctly drop in the 3rd-place ranking. If this is unwanted, change it to `basePoints`, but be aware it violates the "Final Points" invariant.

---

## 8. File-by-File Reference Map

### Domain & Models
| File Path | Purpose | World Cup Modifications |
| :--- | :--- | :--- |
| `models/league_format.dart` | Enum definition | Added `worldCup` (index 3). Added `isWorldCup`, `hasGroups`, `hasKnockout` getters. |
| `models/league_settings.dart` | Settings model | Added `WorldCupFormat` enum. Added `worldCupFormat` field with safe string serialization. |
| `models/enums.dart` | Misc enums | Added `WorldCupQualificationSlot`. |
| `models/league.dart` | League model | Added `isWorldCup` and `worldCupFormat` convenience getters. |
| `models/team.dart` | Team model | **No changes.** Relies on existing `groupId` string field. |
| `domain/standings/standings.dart` | Row model | **No changes.** |
| `domain/standings/standings_calculator.dart` | Tie-breaker logic | Added `fifaGroupTieBreakers` flag and H2H cluster resolution algorithm. |

### Engine & Logic
| File Path | Purpose | World Cup Modifications |
| :--- | :--- | :--- |
| `logic/fixture_generator.dart` | Match creation | Added `generateWorldCupGroupStage()`. Enforces single RR and 4-team groups. |
| `domain/logic/tournament_controller.dart` | Seeding & Advancement | Added `seedWorldCupKnockouts32()`, `seedWorldCupKnockouts48()`. Updated `_buildKnockoutTree` to support R32. |
| `logic/standings_engine.dart` | Legacy sorting | **No changes.** (World Cup uses `StandingsCalculator`). |

### UI / Presentation
| File Path | Purpose | World Cup Modifications |
| :--- | :--- | :--- |
| `presentation/league_creation_dashboard.dart` | Creation UI | Added World Cup card, format selector, locked maxTeams logic. |
| `presentation/league_create_wizard.dart` | Wizard UI | Added World Cup chip, format cards, settings injection. |
| `presentation/add_teams_screen.dart` | Team onboarding | Added `_isWorldCup` flag, auto-group assignment for A-L. |
| `presentation/group_draw_screen.dart` | Draw UI | Added Groups I-L support, World Cup fixture generation routing. |
| `presentation/fixtures_screen.dart` | Fixtures list | Added `_isGroupedFormat` getter to show group filter for WC. |
| `presentation/admin_score_mgmt_screen.dart` | Group score admin | Added `_isGroupedFormat`, group label formatting, R32 awareness. |
| `presentation/admin_knockout_score_mgmt_screen.dart` | KO score admin | Added `'Round of 32'` to `_roundOrder` and display names. |
| `presentation/league_standings_screen.dart` | Standings table | Added grouped standings UI, qualification legend for R32/R16. |
| `presentation/knockout_bracket_screen.dart` | Bracket UI | Added `'Round of 32'` to `_roundOrder` and display names. |
| `presentation/league_detail_screen.dart` | League Hub | Added "Generate World Cup Knockouts" admin button. |

### Data / Repositories
| File Path | Purpose | World Cup Modifications |
| :--- | :--- | :--- |
| `data/leagues_repository_local.dart` | Local cache | Added `'Round of 32'` to `roundOrder` sorting array. |
| `data/leagues_repository_firebase.dart` | Firestore writes | **No changes.** Relies on generic `League.toJson()`. |

---

## 9. Testing & QA Checklist

Before deploying any changes to the World Cup engine, run through this manual QA matrix:

### Phase 1: Creation & Setup
- [ ] Create a 32-team World Cup. Verify `maxTeams` is locked to 32.
- [ ] Create a 48-team World Cup. Verify `maxTeams` is locked to 48.
- [ ] Verify Home/Away toggle is hidden and forced to `false`.
- [ ] Add exactly 32/48 teams. Verify auto-assignment creates exactly 8 or 12 groups of 4.

### Phase 2: Group Stage
- [ ] Generate fixtures. Verify exactly 48 matches (32-team) or 72 matches (48-team).
- [ ] Verify every team plays exactly 3 matches.
- [ ] Update scores for all group matches.
- [ ] Verify Standings screen correctly calculates Points, GD, GF.
- [ ] **Tie-Breaker Test:** Manually set scores so 3 teams tie on all metrics. Verify H2H cluster resolution correctly orders them.

### Phase 3: Knockout Generation
- [ ] Click "Generate World Cup Knockouts".
- [ ] **32-Team:** Verify R16 pairings match official FIFA (1A vs 2B, etc.).
- [ ] **48-Team:** Verify 8 best 3rd-place teams are selected. Verify R32 pairings match the A-H / I-L split logic.
- [ ] Verify the 3rd Place match is created and wired to Semi-Final losers.

### Phase 4: Knockout Execution
- [ ] Update R32/R16 scores. Verify winners advance to the correct home/away slots in the next round.
- [ ] **Draw Test:** Set a knockout match score to a draw (e.g., 2-2). Verify the "Penalty Winner" prompt appears.
- [ ] Verify the selected penalty winner advances, not the team with the higher away goals (away goals rule is disabled in this engine).
- [ ] Verify Semi-Final losers are automatically routed to the 3rd Place match.
- [ ] Verify the Final match correctly displays the trophy icon and winner status.

### Phase 5: Regression Testing (CRITICAL)
- [ ] Create a Classic League. Verify it works exactly as before.
- [ ] Create a UCL Group League. Verify 16/32 team seeding works.
- [ ] Create a UCL Swiss League. Verify Playoff and R16 generation works.
- [ ] Verify old leagues (created before this update) load without crashing or showing World Cup UI elements.

---

## 📝 Final Developer Notes

*   **Do not hardcode group names.** Always use `_allGroupNamesAtoL` or generate them dynamically based on `groupCount`. If FIFA introduces a 64-team format in the future, you only need to update the `WorldCupFormat` enum and the group name array.
*   **Admin Adjustments:** The engine respects `adminAdjustment` in `finalPoints`. If an admin deducts 3 points from a team for a rule violation, that team *will* drop in the standings and potentially miss qualification. This is intentional and matches the "Final Points" invariant.
*   **Performance:** The H2H cluster resolution is $O(N^2)$ where $N$ is the cluster size (max 4). This is computationally trivial and safe to run on the main UI thread during standings calculation.
*   **Firestore Limits:** A 48-team World Cup generates 72 group matches + 31 knockout matches = 103 matches. This is well within Firestore batch write limits (500 ops) and document read limits. No pagination is required for the admin score management screen.

***End of Documentation***
