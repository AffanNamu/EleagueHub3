// lib/algorithms/deterministicRandom.ts
//
// Small seeded-PRNG utilities shared by swissPairing.ts and
// worldCupGrouping.ts — anywhere a draw/shuffle needs to be reproducible
// for a given league (same league always gets the same draw across
// sessions/devices) rather than truly random every render.

export function fnv1a32(input: string): number {
  const fnvOffsetBasis = 0x811c9dc5;
  const fnvPrime = 0x01000193;
  let hash = fnvOffsetBasis;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, fnvPrime) >>> 0;
  }
  return hash & 0x7fffffff;
}

/** Small seeded PRNG (mulberry32) — deterministic per seed, unlike Math.random(). */
export function makeRandom(seed: number) {
  let a = seed >>> 0;
  return {
    next(): number {
      a |= 0;
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    },
    nextInt(maxExclusive: number): number {
      return Math.floor(this.next() * maxExclusive);
    },
  };
}

export function shuffle<T>(list: T[], rand: ReturnType<typeof makeRandom>): T[] {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = rand.nextInt(i + 1);
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}
