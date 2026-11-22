import 'package:eleaguehub3/core/services/payments/google_play_billing_catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// On the App Store, `organizer_verification` exists as a yearly
// auto-renewable subscription, while the app sells verification as a
// one-time fee. iOS must therefore buy the separate consumable IDs; Google
// Play keeps its original one-time product IDs.
void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('iOS buys the App Store one-time verification products', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(GooglePlayBillingCatalog.organizerVerificationProductId,
        'organizer_verification_fee');
    expect(GooglePlayBillingCatalog.organizerVerificationRenewalProductId,
        'organizer_verification_renewal_fee');
  });

  test('Android keeps the Google Play verification products', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(GooglePlayBillingCatalog.organizerVerificationProductId,
        'organizer_verification');
    expect(GooglePlayBillingCatalog.organizerVerificationRenewalProductId,
        'organizer_verification_renewal');
  });

  test('the App Store subscription ID is never what iOS buys', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(GooglePlayBillingCatalog.organizerVerificationProductId,
        isNot(GooglePlayBillingCatalog.organizerVerificationId));
  });

  test('every verification ID is recognised as a verification product', () {
    for (final id in [
      'organizer_verification',
      'organizer_verification_renewal',
      'organizer_verification_fee',
      'organizer_verification_renewal_fee',
    ]) {
      expect(GooglePlayBillingCatalog.isOrganizerVerificationProduct(id),
          isTrue,
          reason: id);
    }
    expect(
        GooglePlayBillingCatalog.isOrganizerVerificationProduct('pro_1mo'),
        isFalse);
  });
}
