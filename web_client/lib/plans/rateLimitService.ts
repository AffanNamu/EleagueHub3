// lib/plans/rateLimitService.ts
//
// Client-side counterpart to the rateLimitWriteValid()/rateLimitOk()
// functions in firestore.rules -- the RULES are the actual security
// boundary (a free user cannot bypass the cap no matter what this module
// does), this just builds the exact document shape those rules expect and
// gives callers a friendly "limit reached" error before attempting a write
// that would otherwise fail with a raw permission-denied.
//
// Mirrors lib/core/services/rate_limit_service.dart exactly (same storage
// shape, same window math) so free-tier users get identical behavior on
// web and mobile -- both platforms write into the same
// users/{uid}/rateLimits/{kind} document and are gated by the same rules.
import {
  doc,
  getDoc,
  runTransaction,
  serverTimestamp,
  Timestamp,
  Transaction,
} from 'firebase/firestore';
import { db } from '@/lib/firebase';

export const RATE_LIMIT_KIND_CHAT_MESSAGES = 'chatMessages';
export const RATE_LIMIT_KIND_FEED_POSTS = 'feedPosts';
export const FREE_CHAT_MESSAGES_PER_DAY = 2;
export const FREE_FEED_POSTS_PER_DAY = 2;

const WINDOW_MS = 24 * 60 * 60 * 1000;

export class RateLimitExceededError extends Error {
  kind: string;

  constructor(kind: string) {
    super(
      kind === RATE_LIMIT_KIND_FEED_POSTS
        ? `You have reached your free daily post limit (${FREE_FEED_POSTS_PER_DAY} per day). Upgrade to Pro or Elite to post without a daily limit.`
        : `You have reached your free daily message limit (${FREE_CHAT_MESSAGES_PER_DAY} per day). Upgrade to Pro or Elite to send without a daily limit.`,
    );
    this.name = 'RateLimitExceededError';
    this.kind = kind;
  }
}

// Mirrors profileHasActivePlan('pro'|'elite') in firestore.rules (the
// activePlanId/planExpiresAtMs fields only -- not the separate legacy
// isPremium/premiumExpiresAtMs flag detectPremiumUser() also checks, since
// that flag does not grant an unlimited rate-limit exemption under the
// rules and treating it as if it did would make a paid-looking client skip
// the counter transaction on a write the rules would still gate).
export async function isPaidPlanActive(uid: string): Promise<boolean> {
  try {
    const snap = await getDoc(doc(db, 'users', uid));
    const data = snap.data() ?? {};
    const activePlanId = typeof data.activePlanId === 'string' ? data.activePlanId.trim() : '';
    if (activePlanId !== 'pro' && activePlanId !== 'elite') return false;
    const planExpiresAtMs = Number(data.planExpiresAtMs) || 0;
    return planExpiresAtMs > Date.now();
  } catch {
    return false;
  }
}

/**
 * Runs `writeMore` inside a transaction that also increments (or starts a
 * fresh rolling 24h window for) the given rate-limit counter, so the
 * counter update and the actual write (a chat message, a feed post) commit
 * together atomically -- matching what the Firestore rules require to
 * consider the counter update "real".
 *
 * Throws RateLimitExceededError if the caller has already used today's
 * quota (checked transactionally, so a race between two rapid sends still
 * can't exceed maxPerDay).
 */
export async function runWithRateLimit({
  uid,
  kind,
  maxPerDay,
  writeMore,
}: {
  uid: string;
  kind: string;
  maxPerDay: number;
  writeMore: (tx: Transaction) => void;
}): Promise<void> {
  const ref = doc(db, 'users', uid, 'rateLimits', kind);

  await runTransaction(db, async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();

    let nextWindowStart: unknown;
    let nextCount: number;

    if (!snap.exists()) {
      nextWindowStart = serverTimestamp();
      nextCount = 1;
    } else {
      const data = snap.data() ?? {};
      const windowStart = data.windowStart as Timestamp | undefined;
      const storedCount = Number(data.count) || 0;
      const windowStartMs = windowStart instanceof Timestamp ? windowStart.toMillis() : 0;

      if (now - windowStartMs > WINDOW_MS) {
        nextWindowStart = serverTimestamp();
        nextCount = 1;
      } else {
        if (storedCount >= maxPerDay) {
          throw new RateLimitExceededError(kind);
        }
        nextWindowStart = windowStart;
        nextCount = storedCount + 1;
      }
    }

    tx.set(ref, { windowStart: nextWindowStart, count: nextCount });
    writeMore(tx);
  });
}
