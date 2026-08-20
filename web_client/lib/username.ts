// lib/username.ts
//
// Exact TypeScript port of lib/features/auth/domain/username_utils.dart.
// Single source of truth for username normalization, validation, and
// reserved-word checks on web — mirrors the Dart file field-for-field so
// behavior matches the app exactly, not just "close enough."

export const USERNAME_MIN_LENGTH = 3;
export const USERNAME_MAX_LENGTH = 20;

// Usernames that must never be assignable by a regular user, either
// automatically or manually. Comparisons are always against the
// lowercase canonical form. Ported verbatim from username_utils.dart.
const RESERVED_USERNAMES = new Set<string>([
  'admin',
  'administrator',
  'root',
  'support',
  'help',
  'staff',
  'moderator',
  'mod',
  'esportlyic',
  'official',
  'system',
  'null',
  'undefined',
  'me',
  'you',
  'user',
  'anonymous',
  'superadmin',
  'owner',
  'team',
  'organizer',
  'organiser',
  'esportlyicteam',
]);

const FORMAT_PATTERN = /^[a-z0-9_]+$/;

/**
 * Strict format check: lowercase letters, numbers, and underscore only,
 * USERNAME_MIN_LENGTH-USERNAME_MAX_LENGTH characters. Does NOT lowercase
 * the input (matches the Dart version) and does NOT check reserved
 * status — see isReserved() / isValidUsername().
 */
export function isValidUsernameFormat(candidate: string): boolean {
  const value = candidate.trim();
  if (value.length < USERNAME_MIN_LENGTH || value.length > USERNAME_MAX_LENGTH) {
    return false;
  }
  return FORMAT_PATTERN.test(value);
}

/** Reserved-word check. Normalizes to lowercase internally either way. */
export function isReservedUsername(candidate: string): boolean {
  return RESERVED_USERNAMES.has(candidate.trim().toLowerCase());
}

/**
 * Combines format + reserved checks into one call. This is the check
 * that should gate any save/reservation attempt.
 */
export function isValidUsername(candidate: string): boolean {
  const lower = candidate.trim().toLowerCase();
  return isValidUsernameFormat(lower) && !isReservedUsername(lower);
}

/**
 * Converts a display name into a normalized username candidate. Strips
 * anything that is not a-z/0-9 (this naturally removes spaces,
 * punctuation, symbols, emoji, AND underscores — matches the Dart
 * version exactly, which is intentionally stricter here than the format
 * regex above), lowercases, and truncates to USERNAME_MAX_LENGTH.
 *
 * Returns an empty string if nothing usable remains — callers must
 * handle that case (fall back to a generic base like "user").
 */
export function normalizeToBaseUsername(displayName: string): string {
  let value = displayName.trim().toLowerCase();
  value = value.replace(/[^a-z0-9]/g, '');
  if (value.length > USERNAME_MAX_LENGTH) {
    value = value.slice(0, USERNAME_MAX_LENGTH);
  }
  return value;
}

/**
 * Pads a too-short base candidate up to USERNAME_MIN_LENGTH using the
 * same stable filler ("user") + '0' right-pad as the Dart version. Only
 * used as a last resort during automatic generation.
 */
export function padToMinLength(base: string): string {
  if (base.length >= USERNAME_MIN_LENGTH) return base;
  const filler = 'user';
  const needed = Math.min(Math.max(USERNAME_MIN_LENGTH - base.length, 0), filler.length);
  let result = base + filler.slice(0, needed);
  while (result.length < USERNAME_MIN_LENGTH) result += '0';
  return result;
}

/**
 * Presentation helper: the canonical stored value has no leading '@';
 * this adds it back for display only. Never store the result.
 */
export function toDisplayUsername(storedUsernameLower: string): string {
  const value = storedUsernameLower.trim();
  return value ? `@${value}` : '';
}
