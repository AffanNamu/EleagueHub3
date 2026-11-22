// Run: npx tsx types/globalChatRequest.test.ts
import { GLOBAL_CHAT_ADMIN_TRANSITIONS, globalChatAdminActionVerb, DEFAULT_GLOBAL_CHAT_TAB } from './globalChatRequest';

let failures = 0;
function assertEqual<T>(actual: T, expected: T, name: string) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    failures++;
    console.error(`FAIL ${name}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
  } else {
    console.log(`PASS ${name}`);
  }
}

// Users join without approval, so admins must be able to remove members and restore removed users.
assertEqual([...GLOBAL_CHAT_ADMIN_TRANSITIONS.approved], ['rejected'], 'member can be removed');
assertEqual([...GLOBAL_CHAT_ADMIN_TRANSITIONS.rejected], ['approved'], 'removed user can be restored');
assertEqual([...GLOBAL_CHAT_ADMIN_TRANSITIONS.pending], ['approved', 'rejected'], 'old pending request can be approved or rejected');
assertEqual(GLOBAL_CHAT_ADMIN_TRANSITIONS.approved.includes('approved'), false, 'no-op approve on a member is refused');
assertEqual(GLOBAL_CHAT_ADMIN_TRANSITIONS.rejected.includes('rejected'), false, 'no-op remove on a removed user is refused');

assertEqual(globalChatAdminActionVerb('pending', 'approved'), 'approve', 'verb: approve');
assertEqual(globalChatAdminActionVerb('pending', 'rejected'), 'reject', 'verb: reject');
assertEqual(globalChatAdminActionVerb('approved', 'rejected'), 'remove', 'verb: remove');
assertEqual(globalChatAdminActionVerb('rejected', 'approved'), 'restore', 'verb: restore');

assertEqual(DEFAULT_GLOBAL_CHAT_TAB, 'approved', 'page opens on the member list');

if (failures > 0) {
  console.error(`${failures} test(s) failed`);
  process.exit(1);
}
console.log('All globalChatRequest tests passed');
