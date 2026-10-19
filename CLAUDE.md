# eSportlyic — CLAUDE.md

eSportlyic is a **live, production** esports/football league management platform with real
users, competitions, fixtures, results, and payment data. Treat every change as something that
will hit real leagues immediately — conservative, backward-compatible, fully verified.

## Repo layout

- `lib/` — the Flutter mobile app (`eleaguehub3`).
- `web_client/` — Next.js web client (public-facing league management + the Football Hub).
- `esportlyic-admin/` — Next.js admin dashboard.
- `firestore.rules` — shared Firestore security rules for all three.
- `test/` — Dart tests (`flutter test`).

All three apps talk to the same Firestore backend. A feature that touches league/fixture data
almost always needs a change on **both** `lib/` (Dart) and `web_client/` (TypeScript), kept in
exact behavioral parity — same business rules, same edge cases, mirrored test coverage.

## Git workflow — always push to `main`

Development happens on a feature/work branch (whatever branch you're given for the session).
**Once a change is committed, tested, and verified, always deploy it to `main` too** — don't
leave finished work sitting only on the work branch. Use this exact sequence after every commit:

```bash
git push -u origin <work-branch>
git fetch origin main
git checkout -B main-deploy-temp origin/main
git cherry-pick <commit-sha>
git push origin main-deploy-temp:main
git checkout <work-branch>
git branch -D main-deploy-temp
```

Before pushing to `origin/main`, re-fetch and confirm `origin/<work-branch>`'s tip still matches
what you expect (another process may have pushed to the same branch) — don't force-push over
divergent history; realign and re-cherry-pick instead.

### Before every commit

Flutter tooling mutates two files as a side effect of running (`flutter analyze`/`flutter pub
get`): `analysis_options.yaml` and `android/local.properties`. Always `git checkout --` them
before staging/committing — they are sandbox noise, not real changes.

### Commit attribution

Every commit should end with the attribution footer currently in effect for the session (check
the system reminder for the exact `Co-Authored-By`/`Claude-Session` lines — they change per
session).

## Core safety invariant

> A running competition has HISTORY. New participants, replacements, or regeneration may change
> the FUTURE. They must never silently rewrite the PAST.

Concretely, for any fixture/match/knockout-bracket change:
- Never delete-and-recreate an entire collection to make a small change — read existing docs,
  compute a plan, write only what actually needs to change.
- A match with a saved result (`isPlayed`/`isFinished`) is never deleted or has its identity
  fields (teams, round, bracket position) rewritten. `firestore.rules`' 
  `fixtureMatchWriteRespectsHistory`/`knockoutMatchWriteRespectsHistory` enforce this server-side
  already — check whether a rule change is even needed before adding one.
- Preserve existing document IDs wherever possible; match ids are deterministic (derived from
  league/round/teams, not random) so retries and concurrent generation converge instead of
  duplicating.
- Never weaken a Firestore rule to make a feature work. Adding a new, narrowly-scoped rule for a
  genuinely new collection is fine; loosening an existing authorization check is not.

## Testing conventions

- **Dart**: `flutter test` from the repo root. Business logic lives in pure, Firestore-free
  `lib/features/*/logic/*.dart` files, unit-tested directly (no emulator, no mocking Firestore).
- **`web_client`**: no test runner is configured. Tests are dependency-free `*.test.ts` files run
  via `npx tsx path/to/file.test.ts`, using small local `assertEqual`/`assertThrows` helpers and
  `process.exit(1)` on failure. Mirror every Dart logic test with an equivalent TS one and vice
  versa.
- Run `flutter analyze` (expect 0 `error`-level issues; pre-existing `info`/`warning` noise is
  normal and not your responsibility to clean up) and `npx tsc --noEmit` in `web_client` before
  every commit.

## Zero-permission locale/region conventions

Two existing "surface Europe first" sort biases set the pattern for any future personalization:
`lib/features/leagues/logic/region_locale_detector.dart` (+ TS mirror) for the organizer-created
leagues list, and `lib/features/football_hub/logic/football_league_region_bias.dart` (+ TS
mirror) for the Football Hub's real-world fixtures feed. Both read only the device/browser's
already-configured locale (`Locale.countryCode` / `navigator.language`'s region subtag) — **never**
the Geolocation API, **never** a permission prompt — and only ever **reorder** results, never hide
or filter them. Follow this shape for any new location-flavored feature.
