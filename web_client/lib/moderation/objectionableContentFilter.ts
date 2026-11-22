// web_client/lib/moderation/objectionableContentFilter.ts
//
// Mirror of lib/core/moderation/objectionable_content_filter.dart -- keep
// the word lists and normalisation identical. Web users post into the same
// feeds, comments, chats and discussions that iOS users read, so the App
// Review 1.2 "filter objectionable material from being posted" safeguard
// has to apply on both clients.

export const OBJECTIONABLE_CONTENT_MESSAGE =
  "This contains language that isn't allowed on eSportlyic. Please edit it and try again.";

export class ObjectionableContentError extends Error {
  constructor(message: string = OBJECTIONABLE_CONTENT_MESSAGE) {
    super(message);
    this.name = 'ObjectionableContentError';
  }
}

// Stored already normalised (lowercase, repeated letters collapsed).
const BLOCKED_WORDS = new Set<string>([
  'fuck', 'fucker', 'fuckers', 'fucking', 'fuckin', 'motherfucker',
  'motherfuckers', 'shit', 'shits', 'shity', 'bulshit', 'bitch',
  'bitches', 'ashole', 'asholes', 'bastard', 'bastards', 'cunt', 'cunts',
  'dickhead', 'dickheads', 'pusy', 'twat', 'wanker', 'whore', 'whores',
  'slut', 'sluts', 'cock', 'cocks', 'cocksucker', 'blowjob', 'dildo',
  'porn', 'porno', 'pornography', 'nudes', 'rape', 'rapist', 'molest',
  'niga', 'nigas', 'nigah', 'fagot', 'fagots', 'fag', 'fags', 'dyke',
  'dykes', 'retard', 'retards', 'retarded', 'trany', 'spic', 'spics',
  'kike', 'kikes', 'wetback', 'wetbacks', 'paki',
  'kys',
]);

// Checked before collapsing repeats (their collapsed form is an innocent word).
const BLOCKED_EXACT_SPELLINGS = new Set<string>(['nigger', 'niggers', 'nigga', 'niggas']);

const BLOCKED_PHRASES: RegExp[] = [/\bkil ?(?:your|ur|yo) ?self\b/];

const SUBSTITUTIONS: Record<string, string> = {
  '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't',
  '@': 'a', '$': 's', '!': 'i', '|': 'i', '€': 'e', '¡': 'i',
};

const NON_LETTER = /[^a-z]+/;
const NON_LETTER_GLOBAL = /[^a-z]+/g;
const REPEATS = /([a-z])\1+/g;
const SPACED_LETTERS = /\b(?:[a-z][\s._-]){2,}[a-z]\b/g;

function substituted(raw: string): string {
  let out = '';
  for (const ch of raw.toLowerCase()) out += SUBSTITUTIONS[ch] ?? ch;
  return out.replace(SPACED_LETTERS, (m) => m.replace(/[\s._-]/g, ''));
}

function collapseRepeats(s: string): string {
  return s.replace(REPEATS, '$1');
}

/** Returns the first blocked term found in [text], or null if it is clean. */
export function findObjectionableContent(text: string): string | null {
  if (!text || text.trim() === '') return null;
  const sub = substituted(text);

  for (const word of sub.split(NON_LETTER)) {
    if (!word) continue;
    if (BLOCKED_EXACT_SPELLINGS.has(word)) return word;
    const collapsed = collapseRepeats(word);
    if (BLOCKED_WORDS.has(collapsed)) return collapsed;
  }

  const spaced = collapseRepeats(sub.replace(NON_LETTER_GLOBAL, ' ')).trim();
  for (const phrase of BLOCKED_PHRASES) {
    const m = spaced.match(phrase);
    if (m) return m[0];
  }
  return null;
}

export function isContentAllowed(text: string): boolean {
  return findObjectionableContent(text) === null;
}

/** Throws ObjectionableContentError when [text] contains a blocked term. */
export function ensureContentAllowed(text: string): void {
  if (findObjectionableContent(text) !== null) {
    throw new ObjectionableContentError();
  }
}
