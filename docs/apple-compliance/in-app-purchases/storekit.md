<!--
Source: https://developer.apple.com/documentation/storekit
Final URL: https://developer.apple.com/tutorials/data/documentation/storekit.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: storekit.json
SHA-256 of raw: 48cfe98aac33772e6ec91b17a618accf803ba8b8a0da20c2652e8e7b190f8af5
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# StoreKit

_Framework_

Platforms: iOS 3.0, iPadOS 3.0, Mac Catalyst 13.0, macOS 10.7, tvOS 9.0, visionOS 1.0, watchOS 6.2

Support Apple In-App Purchases and interactions with the App Store.

### Overview

Use the StoreKit framework to provide the following features and services for your apps and Apple In-App Purchases:

- **Apple In-App Purchase**: Offer and promote Apple In-App Purchases for content and services.

- **App transaction**: Verify a customer’s app purchase with an App Store-signed transaction.

- **Messages**: Control the display of App Store messages in your app.

- **Reviews**: Request App Store reviews and ratings from your customers.

- **Recommendations**: Provide recommendations for third-party content that customers can purchase from the App Store.

- **Ad network attribution**: Validate advertisement-driven app installations. See [AdAttributionKit](https://developer.apple.com/documentation/adattributionkit) for app ad campaigns on the App Store and alternative marketplaces.

The StoreKit framework also provides functionality for [External Purchase](https://developer.apple.com/documentation/storekit/external-purchase), [External link account](https://developer.apple.com/documentation/storekit/external-link-account), [PaymentMethodBinding](https://developer.apple.com/documentation/storekit/paymentmethodbinding), and [StoreDownloaderExtension](https://developer.apple.com/documentation/storekit/storedownloaderextension).

## Apple In-App Purchase

- [Apple In-App Purchase](https://developer.apple.com/documentation/storekit/in-app-purchase) — Offer content and services in your app across Apple platforms using a Swift-based interface.

- [Understanding StoreKit workflows](https://developer.apple.com/documentation/storekit/understanding-storekit-workflows) — Implement an in-app store with several product types, using StoreKit views.

- [Getting started with Apple In-App Purchase using StoreKit views](https://developer.apple.com/documentation/storekit/getting-started-with-in-app-purchases-using-storekit-views) — Set up an in-app store using SwiftUI and StoreKit views.

## App transaction

- [Supporting business model changes by using the app transaction](https://developer.apple.com/documentation/storekit/supporting-business-model-changes-by-using-the-app-transaction) — Access the app transaction to determine when a customer purchased an app and the features to which they’re entitled.

- [AppTransaction](https://developer.apple.com/documentation/storekit/apptransaction) — Information that represents the customer’s purchase of the app, cryptographically signed by the App Store.

## Messages

- [Message](https://developer.apple.com/documentation/storekit/message) — An instance for receiving and displaying App Store messages in your app.

- [Message.Reason](https://developer.apple.com/documentation/storekit/message/reason-swift.struct) — Reasons for the App Store messages.

- [DisplayMessageAction](https://developer.apple.com/documentation/storekit/displaymessageaction) — An instance that asks StoreKit to display an App Store message, if appropriate.

## Reviews

- [Requesting App Store reviews](https://developer.apple.com/documentation/storekit/requesting-app-store-reviews) — Implement best practices for prompting users to review your app in the App Store.

- [RequestReviewAction](https://developer.apple.com/documentation/storekit/requestreviewaction) — An instance that tells StoreKit to request an App Store rating or review, if appropriate.

- [SKStoreReviewController](https://developer.apple.com/documentation/storekit/skstorereviewcontroller) — An object that controls the process of requesting App Store ratings and reviews from customers.

## Recommendations

- [Offering media for sale in your app](https://developer.apple.com/documentation/storekit/offering-media-for-sale-in-your-app) — Allow users to purchase media in the App Store from within your app.

- [SKStoreProductViewController](https://developer.apple.com/documentation/storekit/skstoreproductviewcontroller) — A view controller that provides a page where customers can purchase media from the App Store.

- [SKOverlay](https://developer.apple.com/documentation/storekit/skoverlay) — A class that displays an overlay you can use to recommend another app or an App Clip’s corresponding full app.

## Background assets extension

- [StoreDownloaderExtension](https://developer.apple.com/documentation/storekit/storedownloaderextension) — An app extension that uses the system implementation to schedule Apple-hosted asset-pack downloads automatically.

## Payment method binding

- [PaymentMethodBinding](https://developer.apple.com/documentation/storekit/paymentmethodbinding) — A binding that makes payment methods available in apps for an Apple Account.

## Ad network attribution

- [Ad network attribution](https://developer.apple.com/documentation/storekit/ad-network-attribution) — Validate advertisement-driven app installations.

## External Purchase

- [External Purchase](https://developer.apple.com/documentation/storekit/external-purchase) — Enable qualifying apps to offer external purchases.

## External link account

- [External link account](https://developer.apple.com/documentation/storekit/external-link-account) — Enable qualifying apps to link to an external website for account creation or management.

## Deprecated

- [SKCloudServiceSetupViewController](https://developer.apple.com/documentation/storekit/skcloudservicesetupviewcontroller) — A view controller that helps people perform setup for a cloud service, like an Apple Music subscription.

- [SKCloudServiceController](https://developer.apple.com/documentation/storekit/skcloudservicecontroller) — An object that determines the current capabilities of a person’s Music library.

## Articles

- [Supporting subscription offer codes in your app](https://developer.apple.com/documentation/storekit/supporting-subscription-offer-codes-in-your-app) — Provide subscription service for customers who redeem offer codes through the App Store or within your app.

- [Using StoreKit in Unity](https://developer.apple.com/documentation/storekit/using-storekit-in-unity) — Provide in-app purchases in Unity-based games using C#.

## Structures

- [RedeemOption](https://developer.apple.com/documentation/storekit/redeemoption) — An option that customizes the behavior of an offer code redemption.

## Related Documentation

- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) — Manage your customers’ App Store transactions from your server.

- [StoreKit Test](https://developer.apple.com/documentation/storekittest) — Create and automate tests in Xcode for your app’s subscription and Apple In-App Purchase transactions, and SKAdNetwork implementations.

- [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications) — Monitor In-App Purchase events in real time and learn of unreported external purchase tokens, with server notifications from the App Store.

- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi) — The data structure that represents an app store connect api resource.

- [Advanced Commerce API](https://developer.apple.com/documentation/advancedcommerceapi) — Support Apple In-App Purchases through the App Store for exceptionally large catalogs of custom one-time purchases, subscriptions, and subscriptions with optional add-ons.

- [App Store Receipts](https://developer.apple.com/documentation/appstorereceipts) — Validate app and In-App Purchase receipts with the App Store.