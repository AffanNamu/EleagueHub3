<!--
Source: https://developer.apple.com/documentation/storekit/product/subscriptioninfo
Final URL: https://developer.apple.com/tutorials/data/documentation/storekit/product/subscriptioninfo.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: storekit-product-subscriptioninfo.json
SHA-256 of raw: bf194551eeb0231f7e38d667991d82eb7de5e39d208127ee1b87d24fc25c1c9d
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# Product.SubscriptionInfo

_Structure_

Platforms: iOS 15.0, iPadOS 15.0, Mac Catalyst 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, watchOS 8.0

Information about an auto-renewable subscription, such as its status, period, subscription group, and subscription offer details.

```swift
struct SubscriptionInfo
```

## Determining the subscription status

- [status](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/status-swift.property) — An array that contains status information for a subscription group, including renewal and transaction information.

- [status(for:)](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/status(for:)) — Gets the subscription status for a subscription group identifier.

- [status(transactionID:)](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/status(transactionid:)) — Gets the subscription status for a transaction ID.

- [Product.SubscriptionInfo.Status](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/status-swift.struct) — The renewal status information for an auto-renewable subscription.

## Identifying the subscription group

- [subscriptionGroupID](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/subscriptiongroupid) — The subscription group identifier for this subscription.

- [groupDisplayName](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/groupdisplayname) — The localized name of the subscription group, suitable for display.

- [groupLevel](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/grouplevel) — The rank of the subscription relative to other subscriptions in the same subscription group.

## Getting the subscription period

- [subscriptionPeriod](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/subscriptionperiod) — The duration of time between subscription renewals.

- [Product.SubscriptionPeriod](https://developer.apple.com/documentation/storekit/product/subscriptionperiod) — Values that represent the duration of time between subscription renewals.

## Getting pricing terms

- [pricingTerms](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/pricingterms-swift.property) — The pricing terms available for the subscription, including its billing plan types and pricing models.

- [Product.SubscriptionInfo.PricingTerms](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/pricingterms-swift.struct) — The billing plan type, pricing model, and offers for one way of paying for an auto-renewable subscription.

- [Product.SubscriptionInfo.BillingPlanType](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/billingplantype) — 

- [Product.SubscriptionInfo.BillingInfo](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/billinginfo) — The price charged at each billing event, and the period between renewals.

- [Product.SubscriptionInfo.BillingPeriod](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/billingperiod) — 

- [Product.SubscriptionInfo.CommitmentInfo](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/commitmentinfo) — 

## Getting introductory offer details

- [isEligibleForIntroOffer](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/iseligibleforintrooffer) — A Boolean value that indicates whether the customer is eligible for an introductory offer.

- [isEligibleForIntroOffer(for:)](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/iseligibleforintrooffer(for:)) — Returns a Boolean value that determines the customer’s eligibility for an introductory offer within the provided subscription group.

- [introductoryOffer](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/introductoryoffer) — Information about the introductory offer available for the auto-renewable subscription.

- [Product.SubscriptionOffer](https://developer.apple.com/documentation/storekit/product/subscriptionoffer) — Information about a subscription offer that you configure in App Store Connect.

## Getting win-back offer details

- [winBackOffers](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/winbackoffers) — An array of available win-back offers for the auto-renewable subscription that you configured in App Store Connect.

## Getting promotional offer details

- [promotionalOffers](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/promotionaloffers) — An array of promotional offers available for the auto-renewable subscription.

## Getting subscription renewal information

- [Product.SubscriptionInfo.RenewalInfo](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/renewalinfo) — The renewal information for an auto-renewable subscription.

- [Product.SubscriptionInfo.RenewalState](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/renewalstate) — The renewal states of auto-renewable subscriptions.

## Checking data sharing consent eligibility

- [Product.SubscriptionInfo.MultiSeatDataSharingConsentEligibility](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/multiseatdatasharingconsenteligibility) — Values that indicate whether you can request consent to share group information for a subscription group.

## Structures

- [Product.SubscriptionInfo.BundledSubscription](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/bundledsubscription) — Properties and functionality specific to auto-renewable subscriptions included in a subscription bundle.

## Instance Properties

- [bundledSubscriptions](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/bundledsubscriptions) — Properties and functionality specific to auto-renewable subscriptions included in a subscription bundle.

## Type Methods

- [multiSeatDataSharingConsentEligibility(originalTransactionID:)](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/multiseatdatasharingconsenteligibility(originaltransactionid:)) — The user’s eligibility to receive the data sharing consent sheet for the specified original transaction’s multi-seat subscription.

## Product and subscription information

- [Implementing a store in your app using the StoreKit API](https://developer.apple.com/documentation/storekit/implementing-a-store-in-your-app-using-the-storekit-api) — Offer Apple In-App Purchases and manage entitlements using signed transactions and status information.

- [Supporting monthly subscriptions with a 12-month commitment](https://developer.apple.com/documentation/storekit/supporting-monthly-subscriptions-with-a-12-month-commitment) — Configure, merchandise, and grant access to a monthly subscription with a 12-month commitment.

- [Managing the life cycle of monthly subscriptions with a 12-month commitment](https://developer.apple.com/documentation/storekit/managing-lifecycle-of-monthly-subscriptions-with-a-12-month-commitment-) — Handle renewals, cancellations, billing issues, refund requests, and price changes, and test subscriptions with a commitment plan.

- [Product](https://developer.apple.com/documentation/storekit/product) — Information about a product that you configure in App Store Connect.

- [SubscriptionInfo](https://developer.apple.com/documentation/storekit/subscriptioninfo) — Information about an auto-renewable subscription.

- [SubscriptionStatus](https://developer.apple.com/documentation/storekit/subscriptionstatus) — Represents the renewal status information for an auto-renewable subscription.