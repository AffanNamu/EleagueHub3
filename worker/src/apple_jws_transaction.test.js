// Run: node worker/src/apple_jws_transaction.test.js
import { looksLikeJws, purchaseFromAppleTransactionPayload } from "./apple_jws_transaction.js";

let failures = 0;
function assertEqual(actual, expected, label) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) {
    failures++;
    console.error(`FAIL ${label}\n  expected: ${e}\n  actual:   ${a}`);
  } else {
    console.log(`ok   ${label}`);
  }
}
function assertThrows(fn, label) {
  try {
    fn();
    failures++;
    console.error(`FAIL ${label} (did not throw)`);
  } catch (_) {
    console.log(`ok   ${label}`);
  }
}

const b64url = (obj) => Buffer.from(JSON.stringify(obj)).toString("base64url");
const sampleJws = `${b64url({ alg: "ES256", x5c: ["a", "b"] })}.${b64url({ productId: "pro_1mo" })}.c2lnbmF0dXJl`;

// ── looksLikeJws ────────────────────────────────────────────────────────────
assertEqual(looksLikeJws(sampleJws), true, "StoreKit 2 JWS is detected");
assertEqual(looksLikeJws(`  ${sampleJws}\n`), true, "surrounding whitespace is tolerated");
assertEqual(
  looksLikeJws("MIIT0wYJKoZIhvcNAQcCoIITxDCCE8ACAQExCzAJBgUrDgMCGgUAMIIDdAYJKoZIhvcNAQcBoIIDZQSCA2Ex+/="),
  false,
  "legacy base64 app receipt is not treated as a JWS"
);
assertEqual(looksLikeJws(""), false, "empty token is not a JWS");
assertEqual(looksLikeJws("a.b"), false, "two segments is not a JWS");
assertEqual(looksLikeJws("a..c"), false, "empty segment is not a JWS");
assertEqual(looksLikeJws("a+b.c.d"), false, "standard-base64 characters are rejected");

// ── purchaseFromAppleTransactionPayload ────────────────────────────────────
const BUNDLE = "com.eleaguehub.app";
const payload = {
  bundleId: BUNDLE,
  productId: "elite_yearly",
  transactionId: "2000000123",
  originalTransactionId: "2000000100",
  expiresDate: 1893456000000,
  environment: "Sandbox",
  type: "Auto-Renewable Subscription",
};
assertEqual(
  purchaseFromAppleTransactionPayload(payload, BUNDLE),
  {
    productId: "elite_yearly",
    transactionId: "2000000123",
    originalTransactionId: "2000000100",
    expiresMs: 1893456000000,
    cancelledMs: 0,
    environment: "Sandbox",
  },
  "verified subscription payload maps to the legacy purchase shape"
);
assertEqual(
  purchaseFromAppleTransactionPayload({ ...payload, revocationDate: 1700000000000 }, BUNDLE).cancelledMs,
  1700000000000,
  "revocationDate surfaces as cancelledMs so refunded purchases are rejected"
);
assertEqual(
  purchaseFromAppleTransactionPayload({ ...payload, expiresDate: undefined }, BUNDLE).expiresMs,
  0,
  "missing expiresDate becomes 0 (fails the existing future-expiry check)"
);
assertThrows(
  () => purchaseFromAppleTransactionPayload({ ...payload, bundleId: "com.other.app" }, BUNDLE),
  "transaction for another app's bundle is rejected"
);
assertThrows(
  () => purchaseFromAppleTransactionPayload({ ...payload, bundleId: undefined }, BUNDLE),
  "transaction without bundleId is rejected"
);
assertThrows(
  () => purchaseFromAppleTransactionPayload({ ...payload, productId: "" }, BUNDLE),
  "transaction without productId is rejected"
);
assertThrows(() => purchaseFromAppleTransactionPayload(null, BUNDLE), "null payload is rejected");

if (failures > 0) {
  console.error(`\n${failures} test(s) failed`);
  process.exit(1);
}
console.log("\nAll apple_jws_transaction tests passed");
