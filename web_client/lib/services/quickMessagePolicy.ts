// Mirrors lib/features/live/logic/quick_message_policy.dart's
// QuickMessagePolicy exactly — same limits, same blocked patterns, same
// default fallback list — so a message that validates on one platform
// validates on the other, and the shared Firestore write
// (users/{uid}.quickMessagesCustom) never gets a value one platform
// would have rejected.

export const QUICK_MESSAGE_MAX_COUNT = 15;
export const QUICK_MESSAGE_MAX_CHARS = 15;

export const QUICK_MESSAGE_DEFAULT_FALLBACK: string[] = [
  'Focus!',
  'Calm down',
  'We got this',
  'One more goal!',
  'Don’t give up',
  'Sorry',
  'Unlucky',
  'What a goal!',
  'Ref??',
];

const BLOCKED_TOKENS = ['fuck', 'shit', 'bitch', 'asshole', 'bastard', 'dick', 'pussy', 'cunt'];

const URL_LIKE = /(https?:\/\/|www\.|\.com\b|\.net\b|\.org\b)/i;
const MENTION_LIKE = /@[\w_]+/i;
const PHONE_LIKE = /(\+?\d[\d\-\s]{6,}\d)/;

export interface QuickMessageValidationResult {
  ok: boolean;
  value: string;
  error: string;
}

export function normalizeQuickMessage(raw: string): string {
  return raw.trim().replace(/\s+/g, ' ');
}

export function validateCustomQuickMessage(raw: string): QuickMessageValidationResult {
  const s = normalizeQuickMessage(raw);
  if (!s) return { ok: false, value: '', error: 'Message is empty' };
  if ([...s].length > QUICK_MESSAGE_MAX_CHARS) {
    return { ok: false, value: '', error: `Max ${QUICK_MESSAGE_MAX_CHARS} characters` };
  }
  if (URL_LIKE.test(s)) return { ok: false, value: '', error: 'Links are not allowed' };
  if (MENTION_LIKE.test(s)) return { ok: false, value: '', error: 'Mentions are not allowed' };
  if (PHONE_LIKE.test(s)) return { ok: false, value: '', error: 'Phone numbers are not allowed' };

  const lower = s.toLowerCase();
  if (BLOCKED_TOKENS.some((t) => lower.includes(t))) {
    return { ok: false, value: '', error: 'Message is not allowed' };
  }

  return { ok: true, value: s, error: '' };
}

export function sanitizeQuickMessageList(raw: string[]): string[] {
  const cleaned: string[] = [];
  for (const m of raw) {
    const v = normalizeQuickMessage(m);
    if (!v) continue;
    cleaned.push(v);
    if (cleaned.length >= QUICK_MESSAGE_MAX_COUNT) break;
  }
  return cleaned;
}
