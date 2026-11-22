<!--
Source: https://developer.apple.com/documentation/storekit/subscriptionstoreview
Final URL: https://developer.apple.com/tutorials/data/documentation/storekit/subscriptionstoreview.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: storekit-subscriptionstoreview.json
SHA-256 of raw: 7fa937306fc1797ed4369a0f68cc2b508d4da2300a7d60c924011b86bbcc83e9
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# SubscriptionStoreView

_Structure_

Platforms: iOS 17.0, iPadOS 17.0, Mac Catalyst 17.0, macOS 14.0, tvOS 17.0, visionOS 1.0, watchOS 10.0

A view that merchandises a collection of auto-renewable subscription options that belong to the same subscription group.

```swift
@MainActor @preconcurrency struct SubscriptionStoreView<Content> where Content : View
```

### Overview

A `SubscriptionStoreView` displays localized information about auto-renewable subscriptions, including their localized names, descriptions, and prices, as well as a purchase button.

Create a subscription store view by using one of the initializers and providing the following information:

- A subscription group identifier

- A collection of product identifiers

- A collection of product values you previously loaded from the App Store

If you provide a subscription group identifier or a collection of product identifiers, the subscription store view automatically loads the subscription data from the App Store, and updates the view when the data is available.

#### Provide a background and a decorative icon

The subscription store view doesn’t draw a background by default. You can add a background as follows:

- To layer a background behind the view, use a view modifier, such as `background(alignment:content:)`.

- To set the container background of the subscription store using a view, use the `containerBackground(_:for:)` or `containerBackground(for:alignment:content:)` view modifier and specify a [ContainerBackgroundPlacement](https://developer.apple.com/documentation/swiftui/containerbackgroundplacement), such as [subscriptionStoreHeader](https://developer.apple.com/documentation/swiftui/containerbackgroundplacement/subscriptionstoreheader).

You can optionally provide a view as a decorative icon next to each subscription option. Use the [subscriptionStoreControlIcon(icon:)](https://developer.apple.com/documentation/swiftui/view/subscriptionstorecontrolicon(icon:)) view modifier to set a view that decorates individual subscription options within a subscription store.

#### Order and filter subscriptions

If you create the subscription store view by providing a subscription group identifier, the system orders the subscription options according to their rank. If the customer is already subscribed, you may want to merchandise upgrade or crossgrade options. By default, the subscription store view lists all the subscriptions in the group. To hide certain subscription options, provide the `visibleRelationships` parameter in the initializer. For more information about the visible relationships, see [Product.SubscriptionRelationship](https://developer.apple.com/documentation/storekit/product/subscriptionrelationship).

If you create the subscription store view using one of the other initializers, the view orders the subscriptions according to the collection parameter’s order. The view excludes subscriptions that you don’t include in the collection parameter.

#### Add terms of service and privacy policies

The `SubscriptionStoreView` automatically displays buttons for the terms of service and privacy policy that you submit in App Store Connect. To override the destination of these buttons with a URL to custom terms of service and privacy policy pages, or a custom view, use the modifiers [subscriptionStorePolicyDestination(url:for:)](https://developer.apple.com/documentation/swiftui/view/subscriptionstorepolicydestination(url:for:)) and [subscriptionStorePolicyDestination(for:destination:)](https://developer.apple.com/documentation/swiftui/view/subscriptionstorepolicydestination(for:destination:)).

Use modifiers, such as [subscriptionStorePolicyForegroundStyle(_:)](https://developer.apple.com/documentation/swiftui/view/subscriptionstorepolicyforegroundstyle(_:)), to customize the button’s style, for example, to make the text more readable against your store’s background.

#### Add auxiliary buttons

You can show auxiliary buttons in the subscription store using view modifiers. Specify the button’s visibility within the subscription store by using the [storeButton(_:for:)](https://developer.apple.com/documentation/swiftui/view/storebutton(_:for:)) view modifier.

If you offer your subscription through other services, you can configure the subscription store view to display a sign-in button. Use the [subscriptionStoreSignInAction(_:)](https://developer.apple.com/documentation/swiftui/view/subscriptionstoresigninaction(_:)) modifier to set the function your app calls when someone uses the sign-in button.

The subscription store view automatically shows a Close button. To override this behavior, use the `storeButton(_:for:)` modifier to unconditionally show, or hide, the Close button.

#### Style the subscription store view

You can further customize the subscription store’s appearance using control styles. Use subscription store control styles to customize the display of subscription options, and how people interact with your store. To try out standard styles, such as [PickerSubscriptionStoreControlStyle](https://developer.apple.com/documentation/storekit/pickersubscriptionstorecontrolstyle), apply the style using the [subscriptionStoreControlStyle(_:)](https://developer.apple.com/documentation/swiftui/view/subscriptionstorecontrolstyle(_:)) modifier.

## Creating subscription store views with automatic marketing content

- [init(groupID:visibleRelationships:)](https://developer.apple.com/documentation/storekit/subscriptionstoreview/init(groupid:visiblerelationships:)) — Creates a view that loads all subscriptions in a subscription group from the App Store, and merchandises them with automatic marketing content.

- [init(productIDs:)](https://developer.apple.com/documentation/storekit/subscriptionstoreview/init(productids:)) — Creates a view that loads subscriptions based on a collection of product identifiers, and merchandises them with automatic marketing content.

- [init(subscriptions:)](https://developer.apple.com/documentation/storekit/subscriptionstoreview/init(subscriptions:)) — Creates a view that displays a collection of subscription options, and merchandises them with automatic marketing content.

## Creating subscription store views with custom marketing content

- [init(groupID:visibleRelationships:marketingContent:)](https://developer.apple.com/documentation/storekit/subscriptionstoreview/init(groupid:visiblerelationships:marketingcontent:)) — Creates a view that loads all the subscriptions in a subscription group from the App Store, and merchandises them with custom marketing content.

- [init(productIDs:marketingContent:)](https://developer.apple.com/documentation/storekit/subscriptionstoreview/init(productids:marketingcontent:)) — Creates a view that loads a collection of subscriptions from the App Store, and merchandises them with custom marketing content.

- [init(subscriptions:marketingContent:)](https://developer.apple.com/documentation/storekit/subscriptionstoreview/init(subscriptions:marketingcontent:)) — Creates a view that displays a collection of subscription options, and merchandises them with custom marketing content.

## Creating subscription store views with a hierarchichal structure

- [init(groupID:visibleRelationships:content:)](https://developer.apple.com/documentation/storekit/subscriptionstoreview/init(groupid:visiblerelationships:content:)) — 

- [init(productIDs:content:)](https://developer.apple.com/documentation/storekit/subscriptionstoreview/init(productids:content:)) — 

- [init(subscriptions:content:)](https://developer.apple.com/documentation/storekit/subscriptionstoreview/init(subscriptions:content:)) — 

## Supporting types

- [AutomaticSubscriptionStoreMarketingContent](https://developer.apple.com/documentation/storekit/automaticsubscriptionstoremarketingcontent) — A view that represents the default marketing content for a subscription store.

- [SubscriptionStoreContentView](https://developer.apple.com/documentation/storekit/subscriptionstorecontentview) — 

## Merchandising Apple In-App Purchases, subscriptions, and offers

- [ProductView](https://developer.apple.com/documentation/storekit/productview) — A view that merchandises an individual Apple In-App Purchase product.

- [StoreView](https://developer.apple.com/documentation/storekit/storeview) — A view that merchandises a collection of Apple In-App Purchase products.

- [SubscriptionOfferView](https://developer.apple.com/documentation/storekit/subscriptionofferview) — 

- [Backyard Birds: Building an app with SwiftData and widgets](https://developer.apple.com/documentation/swiftui/backyard-birds-sample) — Create an app with persistent data, interactive widgets, and an all new in-app purchase experience.