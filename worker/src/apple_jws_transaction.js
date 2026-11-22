// worker/src/apple_jws_transaction.js
//
// StoreKit 2 support for App Store purchase verification.
//
// in_app_purchase_storekit >= 0.4.0 uses StoreKit 2 by default on every
// device running iOS 15+ (this app's minimum), and its
// PurchaseDetails.verificationData.serverVerificationData is then the
// transaction's JWS representation -- not the base64 app receipt that
// Apple's legacy verifyReceipt endpoint expects. Sending a JWS to
// verifyReceipt fails (status 21002), so a StoreKit 2 purchase could never
// activate a plan. index.js verifies the JWS signature with the same pinned
// Apple root it already uses for App Store Server Notifications V2, then
// uses the helpers below to turn the verified payload into the purchase
// shape the existing activation code consumes.
//
// Kept free of Worker/Web Crypto dependencies so it can be unit-tested with
// plain Node (see apple_jws_transaction.test.js).

const BASE64URL_SEGMENT = /^[A-Za-z0-9_-]+={0,2}$/;

// A legacy app receipt is one long standard-base64 string (it contains
// '+', '/' and no '.'); a JWS is exactly three base64url segments joined
// by '.'. Used only to choose a verification path -- the JWS signature is
// verified separately before anything in it is trusted.
export function looksLikeJws(token) {
  const parts = String(token || "").trim().split(".");
  return parts.length === 3 && parts.every((p) => p.length > 0 && BASE64URL_SEGMENT.test(p));
}

// Maps a signature-verified JWSTransactionDecodedPayload to the purchase
// object returned by the legacy receipt path in index.js, so both paths
// feed identical downstream checks (product -> plan mapping, requested
// plan/duration match, future expiry, revocation).
//
// Throws when the transaction belongs to a different app, so a validly
// Apple-signed transaction for some other bundle can never activate a plan
// here.
export function purchaseFromAppleTransactionPayload(payload, expectedBundleId) {
  if (!payload || typeof payload !== "object") {
    throw new Error("App Store transaction payload is empty.");
  }

  const bundleId = String(payload.bundleId || "").trim();
  if (!bundleId || bundleId !== expectedBundleId) {
    throw new Error(
      `App Store transaction is for bundle "${bundleId || "(none)"}", not "${expectedBundleId}".`
    );
  }

  const productId = String(payload.productId || "").trim();
  if (!productId) {
    throw new Error("App Store transaction has no productId.");
  }

  return {
    productId,
    transactionId: String(payload.transactionId || "").trim(),
    originalTransactionId: String(payload.originalTransactionId || "").trim(),
    expiresMs: Number(payload.expiresDate || 0),
    cancelledMs: payload.revocationDate ? Number(payload.revocationDate) : 0,
    environment: String(payload.environment || "").trim(),
  };
}
