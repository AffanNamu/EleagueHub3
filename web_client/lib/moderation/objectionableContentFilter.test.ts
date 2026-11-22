// Run: npx tsx lib/moderation/objectionableContentFilter.test.ts
// Mirrors test/objectionable_content_filter_test.dart case-for-case.
import {
  ensureContentAllowed,
  findObjectionableContent,
  isContentAllowed,
  ObjectionableContentError,
  OBJECTIONABLE_CONTENT_MESSAGE,
} from './objectionableContentFilter';

let failures = 0;
function assertEqual<T>(actual: T, expected: T, label: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    failures++;
    console.error(`FAIL ${label}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`);
  } else {
    console.log(`ok   ${label}`);
  }
}
function assertThrows(fn: () => void, label: string) {
  try {
    fn();
    failures++;
    console.error(`FAIL ${label} (did not throw)`);
  } catch (e) {
    assertEqual(e instanceof ObjectionableContentError, true, `${label} throws ObjectionableContentError`);
  }
}

const blocked = [
  'what the fuck was that',
  'FUCK',
  'you absolute sh1t',
  'b!tch please',
  'fuuuuck this ref',
  'f u c k off',
  'what an asshole',
  'go kill yourself',
  'kill urself',
  'kys',
  'nigger',
  'send nudes',
  'he is a faggot',
];
for (const text of blocked) {
  assertEqual(isContentAllowed(text), false, `blocks "${text}"`);
  assertThrows(() => ensureContentAllowed(text), `ensureContentAllowed("${text}")`);
}

const allowed = [
  '',
  '   ',
  'Great match today! 3-1 win',
  'Niger vs Nigeria friendly this Saturday',
  'Dick Advocaat named new coach',
  'That was a chink in their armour',
  'Scunthorpe United are top of the league',
  'Classic counter attack, he will shoot on sight',
  'You need to improve your skill yourself',
  'We will kill the game in the second half',
  'Assist of the season',
  'Bass player Cocky striker Cockerill',
  'Coach said: grass was wet',
  'Van Dijk wins the duel',
  'الفريق لعب بشكل رائع',
  'Goal!!!',
  '$100 prize pool for the tournament',
];
for (const text of allowed) {
  assertEqual(findObjectionableContent(text), null, `allows "${text}"`);
}

assertEqual(new ObjectionableContentError().message, OBJECTIONABLE_CONTENT_MESSAGE, 'error carries the user-facing message');

if (failures > 0) {
  console.error(`\n${failures} test(s) failed`);
  process.exit(1);
}
console.log('\nAll objectionableContentFilter tests passed');
