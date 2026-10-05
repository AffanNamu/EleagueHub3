// web_client/lib/leagues/sessionOptions.ts
//
// Pure helpers for the Competition Session picker -- mirrors
// lib/features/leagues/logic/competition_session_options.dart exactly (same
// algorithm, same max length) so the web and Flutter clients always offer
// identical options and the same validation for the same League.season
// field (a plain string -- "2026", "2026/2027", "Summer 2027", or any other
// organizer-chosen label; see that Dart file's doc comment for why).
//
// These helpers never decide what gets stored: they only (a) suggest a
// starting set of options for the picker UI, and (b) validate a custom
// value the organizer types in. The organizer's choice is always final.

/** Mirrors firestore.rules' size cap on League.season. */
export const SESSION_MAX_LENGTH = 60;

/**
 * Dynamically generates six likely session values anchored to `now`
 * (defaults to the real current time) -- never a fixed year, so this keeps
 * producing sensible options in 2027, 2028, 2029, ... without a code
 * change. Three single calendar years (current, next, the one after)
 * followed by three year-range sessions.
 */
export function generateSessionOptions(now: Date = new Date()): string[] {
  const year = now.getFullYear();
  return [
    `${year}`,
    `${year + 1}`,
    `${year + 2}`,
    `${year}/${year + 1}`,
    `${year + 1}/${year + 2}`,
    `${year + 2}/${year + 3}`,
  ];
}

/**
 * A single pre-filled suggestion for a brand-new competition -- the
 * current/next year range. Only a convenience default: the organizer can
 * change it to any other generated option or a fully custom value before
 * creating the competition.
 */
export function suggestedDefaultSession(now: Date = new Date()): string {
  const year = now.getFullYear();
  return `${year}/${year + 1}`;
}

/**
 * Validates and trims a custom session string the organizer typed in.
 * Returns null if the value is empty (after trimming) or exceeds
 * SESSION_MAX_LENGTH -- callers should show a validation error in that
 * case, never silently fall back to a default.
 */
export function normalizeCustomSession(input: string): string | null {
  const trimmed = input.trim();
  if (!trimmed) return null;
  if (trimmed.length > SESSION_MAX_LENGTH) return null;
  return trimmed;
}
