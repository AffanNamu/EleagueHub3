<!--
Source: https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(in:)
Final URL: https://developer.apple.com/tutorials/data/documentation/storekit/appstore/showmanagesubscriptions(in:).json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: storekit-show-manage-subscriptions.json
SHA-256 of raw: 0414a9e4b2f93a7af64ed110325c21e100f4792e895752996cacaf523f8c1037
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# showManageSubscriptions(in:)

_Type Method_

Platforms: iOS 15.0, iPadOS 15.0, Mac Catalyst 15.0, visionOS 1.0

Presents the App Store sheet for managing subscriptions.

```swift
@MainActor static func showManageSubscriptions(in scene: UIWindowScene) async throws
```

## Parameters

- **scene**: The [UIWindowScene](https://developer.apple.com/documentation/uikit/uiwindowscene) that the system displays the sheet on.

### Discussion

Use this function to display the manage subscriptions sheet within your app. Consider adding a manage subscriptions option to your app. For design guidance on supporting this functionality, see [Human Interface Guidelines > Apple In-App Purchase > Helping People Manage Their Subscriptions](https://developer.apple.com/design/human-interface-guidelines/in-app-purchase/overview/auto-renewable-subscriptions/#helping-people-manage-their-subscriptions).

The [showManageSubscriptions(in:)](https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(in:)) function presents a manage subscription sheet that’s the same as what customers can view in their account settings in the App Store app or by choosing Settings > Apple Account > Subscriptions on an iOS or iPadOS device. The sheet displays the customer’s currently active subscription for your app and the options to view, upgrade, downgrade, or cancel their subscription. For a multiseat subscription, the group purchaser can also change the number of seats and, with Apple-hosted invitations, manage the group’s members.

If you’re using SwiftUI, call the [manageSubscriptionsSheet(isPresented:)](https://developer.apple.com/documentation/swiftui/view/managesubscriptionssheet(ispresented:))view modifier.

Mac apps built with Mac Catalyst can use this method in Mac Catalyst 27.3 and later, and AppKit apps use [showManageSubscriptions(from:)](https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(from:)) in macOS 27.3 and later. Earlier versions of macOS don’t support the sheet, so avoid showing the user interface for this feature there:

- In Mac apps built with Mac Catalyst, check the version at runtime with `if #available(macCatalyst 27.3, *)`. For more information on Mac Catalyst, see [Creating a Mac version of your iPad app](https://developer.apple.com/documentation/uikit/creating-a-mac-version-of-your-ipad-app).

- For iOS apps running on Apple silicon, if [isiOSAppOnMac](https://developer.apple.com/documentation/foundation/processinfo/isiosapponmac) is `true,` avoid showing the user interface for this feature.

#### Test managing subscriptions

Test the managing subscriptions functionality in the sandbox environment and StoreKit testing in Xcode. For more information about testing, see [Testing at all stages of development with Xcode and the sandbox](https://developer.apple.com/documentation/storekit/testing-at-all-stages-of-development-with-xcode-and-the-sandbox) and [Setting up StoreKit Testing in Xcode](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode).

## Managing subscriptions

- [showManageSubscriptions(in:subscriptionGroupID:)](https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(in:subscriptiongroupid:)) — Presents the App Store sheet for managing subscriptions for a subscription group.

- [showManageSubscriptions(from:)](https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(from:)) — Presents the App Store sheet for managing subscriptions.

- [showManageSubscriptions(from:subscriptionGroupID:)](https://developer.apple.com/documentation/storekit/appstore/showmanagesubscriptions(from:subscriptiongroupid:)) — Presents the App Store sheet for managing subscriptions for a subscription group.