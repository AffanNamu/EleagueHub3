<!--
Source: https://developer.apple.com/documentation/storekit/in-app-purchase
Final URL: https://developer.apple.com/tutorials/data/documentation/storekit/in-app-purchase.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: storekit-in-app-purchase.json
SHA-256 of raw: 7acba0fb1361a87c89a62bdd5826f31e8de1ff297431cc433b980ba461a43b75
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# Apple In-App Purchase

_API Collection_

Offer content and services in your app across Apple platforms using a Swift-based interface.

### Overview

With the Apple In-App Purchase API, you can offer customers the opportunity to purchase digital content and services in your app. Customers can make the purchases within your app, and find your promoted products on the App Store.

The StoreKit framework connects to the App Store on your app’s behalf to prompt for, and securely process, payments. The framework then notifies your app, making the transactions for Apple In-App Purchases available to your app on all of the customer’s devices. For each transaction that represents a current purchase, your app delivers the purchased products. To validate purchases, you can verify transactions on your server, or rely on StoreKit’s verification.

[image]

The App Store can also communicate with your server. It notifies your server of transactions and auto-renewable subscription events through [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications), and provides the same transaction information, and more, through the [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi).

To learn how adding Apple In-App Purchases fits in an overall app development workflow for the App Store, see [App Store Pathway](https://developer.apple.com/app-store/pathway/). For an overview of Apple In-App Purchases and its features, including its configuration, testing capabilities, marketing for your products, and more, see [Simple and safe Apple In-App Purchases](https://developer.apple.com/in-app-purchase/). For an overview on subscriptions, including creating subscription groups, Family Sharing, and more, see [Auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/).

#### Configure Apple In-App Purchases

To use the Apple In-App Purchase API, you first need to configure the products that your app merchandises.

- In the early stages of development, you can configure the products in the StoreKit configuration file in Xcode, and test your code without any dependency on App Store Connect. For more information, see [Setting up StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode).

- When you’re ready for sandbox testing and production, configure the products in App Store Connect. You can add or remove products and refine or reconfigure existing products as you develop your app. For more information, see [Configure Apple In-App Purchase settings](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases).

You can also offer apps and Apple In-App Purchases that run on multiple platforms as a single purchase. For more information on universal purchase, see [Add platforms](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-platforms/).

#### Support a store in your app

The Apple In-App Purchase API takes advantage of Swift features like concurrency to simplify your Apple In-App Purchase workflows, and SwiftUI to build stores with [StoreKit views](https://developer.apple.com/documentation/storekit/storekit-views). Use the API to manage access to content and subscriptions, receive App Store-signed transaction information, get the history of all Apple In-App Purchase transactions, and more.

> **Related sessions from WWDC21:** Session 10114: [Meet StoreKit 2](https://developer.apple.com/videos/play/wwdc2021/10114/)

The Apple In-App Purchase API offers:

- Transaction information that’s App Store-signed in JSON Web Signature (JWS) format.

- Transaction and subscription status information that’s simple to parse in your app.

- An entitlements API, [currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements), that simplifies determining entitlements to unlock content and services for your customers.

> **Related sessions from WWDC22:** Session 110404: [Implement proactive Apple In-App Purchase restore](https://developer.apple.com/videos/play/wwdc2022/110404/)

To support a store in your app, implement the following functionality:

- Listen for transaction state changes using the transaction listener, [updates](https://developer.apple.com/documentation/storekit/transaction/updates), to provide up-to-date service and content while your app is running.

- Use [StoreKit views](https://developer.apple.com/documentation/storekit/storekit-views) to merchandise your products; or request products to display from the App Store with [products(for:)](https://developer.apple.com/documentation/storekit/product/products(for:)) and enable purchases using [purchase(options:)](https://developer.apple.com/documentation/storekit/product/purchase(options:)). Unlock purchased content and services based on the purchase result, [Product.PurchaseResult](https://developer.apple.com/documentation/storekit/product/purchaseresult).

- Iterate through a customer’s purchases anytime using the transaction sequence [all](https://developer.apple.com/documentation/storekit/transaction/all), and unlock the purchased content and services.

- Optionally, validate the signed transactions and signed subscription status information that you receive from the API.

## Apple In-App Purchase merchandising

- [StoreKit views](https://developer.apple.com/documentation/storekit/storekit-views) — Display a customizable Apple In-App Purchase store using StoreKit views for SwiftUI.

## Product and subscription information

- [Implementing a store in your app using the StoreKit API](https://developer.apple.com/documentation/storekit/implementing-a-store-in-your-app-using-the-storekit-api) — Offer Apple In-App Purchases and manage entitlements using signed transactions and status information.

- [Supporting monthly subscriptions with a 12-month commitment](https://developer.apple.com/documentation/storekit/supporting-monthly-subscriptions-with-a-12-month-commitment) — Configure, merchandise, and grant access to a monthly subscription with a 12-month commitment.

- [Managing the life cycle of monthly subscriptions with a 12-month commitment](https://developer.apple.com/documentation/storekit/managing-lifecycle-of-monthly-subscriptions-with-a-12-month-commitment-) — Handle renewals, cancellations, billing issues, refund requests, and price changes, and test subscriptions with a commitment plan.

- [Product](https://developer.apple.com/documentation/storekit/product) — Information about a product that you configure in App Store Connect.

- [Product.SubscriptionInfo](https://developer.apple.com/documentation/storekit/product/subscriptioninfo) — Information about an auto-renewable subscription, such as its status, period, subscription group, and subscription offer details.

- [SubscriptionInfo](https://developer.apple.com/documentation/storekit/subscriptioninfo) — Information about an auto-renewable subscription.

- [SubscriptionStatus](https://developer.apple.com/documentation/storekit/subscriptionstatus) — Represents the renewal status information for an auto-renewable subscription.

## Multiseat subscriptions

- [Supporting multiseat purchases in your app](https://developer.apple.com/documentation/storekit/supporting-multiseat-purchases-in-your-app) — Configure, merchandise, and sell subscriptions that people buy for a group or that organizations buy in volume, and grant access to every seat.

- [Hosting group invitations in your app](https://developer.apple.com/documentation/storekit/hosting-group-invitations-in-your-app) — Run your own invitation flow for group subscriptions, and keep the App Store informed of which seats your members hold.

- [Managing the life cycle of multiseat subscriptions](https://developer.apple.com/documentation/storekit/managing-the-life-cycle-of-multiseat-subscriptions) — Handle added and removed seats, member changes, plan changes, cancellations, billing issues, refunds, and price changes for multiseat subscriptions.

## Purchase requests and results

- [PurchaseAction](https://developer.apple.com/documentation/storekit/purchaseaction) — An action that starts an Apple In-App Purchase.

- [purchase(options:)](https://developer.apple.com/documentation/storekit/product/purchase(options:)) — Initiates a purchase for the product with the App Store and displays the confirmation sheet.

- [Product.PurchaseResult](https://developer.apple.com/documentation/storekit/product/purchaseresult) — The result of a purchase.

## Transaction history and entitlements

- [Transaction](https://developer.apple.com/documentation/storekit/transaction) — Information that represents the customer’s purchase of a product in your app.

- [updates](https://developer.apple.com/documentation/storekit/transaction/updates) — The asynchronous sequence that emits a transaction when the system creates or updates transactions that occur outside the app or on other devices.

- [all](https://developer.apple.com/documentation/storekit/transaction/all) — A sequence that emits all the customer’s transactions for your app.

- [currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements) — A sequence of the latest transactions that entitle a customer to Apple In-App Purchases and subscriptions.

## JWS verification

- [VerificationResult](https://developer.apple.com/documentation/storekit/verificationresult) — A type that describes the result of a StoreKit verification.

- [VerificationResult.VerificationError](https://developer.apple.com/documentation/storekit/verificationresult/verificationerror) — Error cases for StoreKit JWS verification.

## Subscription status and renewal information

- [Product.SubscriptionInfo.Status](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/status-swift.struct) — The renewal status information for an auto-renewable subscription.

- [Product.SubscriptionInfo.RenewalInfo](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/renewalinfo) — The renewal information for an auto-renewable subscription.

- [SubscriptionRenewalInfo](https://developer.apple.com/documentation/storekit/subscriptionrenewalinfo) — Represents the renewal information for an auto-renewable subscription.

- [Product.SubscriptionInfo.RenewalState](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/renewalstate) — The renewal states of auto-renewable subscriptions.

- [SubscriptionRenewalState](https://developer.apple.com/documentation/storekit/subscriptionrenewalstate) — The renewal states of auto-renewable subscriptions.

- [SubscriptionPeriod](https://developer.apple.com/documentation/storekit/subscriptionperiod) — Represents the duration of time between subscription renewals.

## Offers

- [Supporting offer codes in your app](https://developer.apple.com/documentation/storekit/supporting-offer-codes-in-your-app) — Enable customers to redeem offer codes through the App Store or within your app.

- [Supporting win-back offers in your app](https://developer.apple.com/documentation/storekit/supporting-win-back-offers-in-your-app) — Re-engage previous subscribers with a free or discounted offer for an auto-renewable subscription, for a specific duration.

- [Merchandising win-back offers in your app](https://developer.apple.com/documentation/storekit/merchandising-win-back-offers-in-your-app) — Present win-back offers to eligible customers in your app with the win-back offer sheet or by implementing custom merchandising.

- [Product.SubscriptionOffer](https://developer.apple.com/documentation/storekit/product/subscriptionoffer) — Information about a subscription offer that you configure in App Store Connect.

- [Product.SubscriptionOffer.OfferType](https://developer.apple.com/documentation/storekit/product/subscriptionoffer/offertype) — The types of offers for auto-renewable subscriptions.

## Promoted Apple In-App Purchases

- [Supporting promoted Apple In-App Purchases in your app](https://developer.apple.com/documentation/storekit/supporting-promoted-in-app-purchases-in-your-app) — Display promoted Apple In-App Purchases on your product page and handle purchases that users initiate on the App Store.

- [PurchaseIntent](https://developer.apple.com/documentation/storekit/purchaseintent) — An instance that emits purchase intents, which indicate that the customer initiated a purchase outside of your app, for your app to complete.

- [Product.PromotionInfo](https://developer.apple.com/documentation/storekit/product/promotioninfo) — Information about a promoted Apple In-App Purchase that customizes its order and visibility on the device.

- [Testing promoted Apple In-App Purchases](https://developer.apple.com/documentation/storekit/testing-promoted-in-app-purchases) — Test your Apple In-App Purchases before making your app available in the App Store.

## App Store interactions

- [AppStore](https://developer.apple.com/documentation/storekit/appstore) — Interactions with the App Store, such as managing subscriptions, verifying devices, authorizing payments, synchronizing transactions, getting the environment, and more.

- [AppTransaction](https://developer.apple.com/documentation/storekit/apptransaction) — Information that represents the customer’s purchase of the app, cryptographically signed by the App Store.

## Storefront information

- [Storefront](https://developer.apple.com/documentation/storekit/storefront) — The region and unique identifier of the App Store storefront for the device.

- [current](https://developer.apple.com/documentation/storekit/storefront/current) — The current App Store storefront for product purchases.

- [updates](https://developer.apple.com/documentation/storekit/storefront/updates) — The asynchronous sequence that emits storefront information when the system updates the storefront.

## Apple In-App Purchase Testing

- [Testing at all stages of development with Xcode and the sandbox](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox) — Verify your implementation of Apple In-App Purchases by testing your code throughout its development.

- [Testing Apple In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox) — Test your implementation of Apple In-App Purchases using real product information and server-to-server transactions in the sandbox environment.

- [Testing refund requests](https://developer.apple.com/documentation/storekit/testing-refund-requests) — Test your app’s implementation of refund requests, and your app’s and server’s handling of approved and declined refunds.

- [Testing win-back offers in Xcode](https://developer.apple.com/documentation/storekit/testing-win-back-offers-in-xcode) — Validate your app’s handling of win-back offers that you configure for the testing environment.

- [Testing Ask to Buy in Xcode](https://developer.apple.com/documentation/storekit/testing-ask-to-buy-in-xcode) — Validate your app’s handling of Ask To Buy in the testing environment.

## Advanced Commerce API interactions

- [AdvancedCommerceProduct](https://developer.apple.com/documentation/storekit/advancedcommerceproduct) — A product configured as a generic SKU in App Store Connect for use with the Advanced Commerce API.

- [Sending Advanced Commerce API requests from your app](https://developer.apple.com/documentation/storekit/sending-advanced-commerce-api-requests-from-your-app) — Send Advanced Commerce API requests from your app that you authorize with a JSON Web Signature (JWS) you generate on your server.

- [Generating JWS to sign App Store requests](https://developer.apple.com/documentation/storekit/generating-jws-to-sign-app-store-requests) — Create signed JSON Web Signature (JWS) strings on your server to authorize your API requests in your app.

## Errors

- [StoreKitError](https://developer.apple.com/documentation/storekit/storekiterror) — StoreKit Apple In-App Purchase error codes.

## Deprecated

- [Choosing a StoreKit API for Apple In-App Purchases](https://developer.apple.com/documentation/storekit/choosing-a-storekit-api-for-in-app-purchases) — Use the latest API to support Apple In-App Purchases in new or existing apps, or the original API to support Apple In-App Purchases in earlier operating systems.

- [Original API for Apple In-App Purchase](https://developer.apple.com/documentation/storekit/original-api-for-in-app-purchase) — Offer additional content and services in your app using the Original Apple In-App Purchase API.

## Apple In-App Purchase

- [Understanding StoreKit workflows](https://developer.apple.com/documentation/storekit/understanding-storekit-workflows) — Implement an in-app store with several product types, using StoreKit views.

- [Getting started with Apple In-App Purchase using StoreKit views](https://developer.apple.com/documentation/storekit/getting-started-with-in-app-purchases-using-storekit-views) — Set up an in-app store using SwiftUI and StoreKit views.