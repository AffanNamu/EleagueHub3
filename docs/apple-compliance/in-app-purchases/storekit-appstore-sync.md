<!--
Source: https://developer.apple.com/documentation/storekit/appstore/sync()
Final URL: https://developer.apple.com/tutorials/data/documentation/storekit/appstore/sync().json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: storekit-appstore-sync.json
SHA-256 of raw: d69f31a8196f6074282862aba53d16cda1d5ed20a142ac354748219805097fa9
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# sync()

_Type Method_

Platforms: iOS 15.0, iPadOS 15.0, Mac Catalyst 15.0, macOS 12.0, tvOS 15.0, visionOS 1.0, watchOS 8.0

Synchronizes your app’s transaction information and subscription status with information from the App Store.

```swift
static func sync() async throws
```

### Discussion

Include some mechanism in your app, such as a Restore Purchases button, to let users restore their Apple In-App Purchases. In rare cases when a user suspects the app isn’t showing all the transactions, call [sync()](https://developer.apple.com/documentation/storekit/appstore/sync()). By calling [sync()](https://developer.apple.com/documentation/storekit/appstore/sync()), you force the app to obtain transaction information and subscription status from the App Store.

> **Important:** Calling [sync()](https://developer.apple.com/documentation/storekit/appstore/sync())displays a system prompt that asks users to authenticate with their App Store credentials. Call this function only in response to an explicit user action, like tapping or clicking a button.

In regular operations, there’s no need to call [sync()](https://developer.apple.com/documentation/storekit/appstore/sync()). StoreKit automatically keeps up to date transaction information and subscription status available to your app. When users reinstall your app or download it on a new device, the app automatically has all transactions available to it upon initial launch. There’s no need for users to ask your app to restore transactions — your app can immediately get the current entitlements using [currentEntitlements](https://developer.apple.com/documentation/storekit/transaction/currententitlements) and transaction history using [all](https://developer.apple.com/documentation/storekit/transaction/all). For more information about transactions, see [Transaction](https://developer.apple.com/documentation/storekit/transaction).