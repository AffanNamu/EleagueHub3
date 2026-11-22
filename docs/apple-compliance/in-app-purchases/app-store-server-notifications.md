<!--
Source: https://developer.apple.com/documentation/appstoreservernotifications
Final URL: https://developer.apple.com/tutorials/data/documentation/appstoreservernotifications.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: app-store-server-notifications.json
SHA-256 of raw: 55056fb312b126ef5490392f77b45c80a646c22a0e7557d9db99b97317497fe9
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# App Store Server Notifications

_Web Service_

Platforms: App Store Server Notifications 1.0

Monitor In-App Purchase events in real time and learn of unreported external purchase tokens, with server notifications from the App Store.

### Overview

App Store Server Notifications is a server-to-server service that sends real-time notifications for In-App Purchase events, and notifications for unreported external purchase tokens. Use the data in the notifications to update your user-account database, and to monitor and respond to in-app purchase refunds. For notifications related to the [External Purchase](https://developer.apple.com/documentation/storekit/external-purchase) API, see [externalPurchaseToken](https://developer.apple.com/documentation/appstoreservernotifications/externalpurchasetoken).

> **Important:** The [App Store Server Notifications V1](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-v1) endpoint and version 1 notifications, [notification_type](https://developer.apple.com/documentation/appstoreservernotifications/notification_type), are deprecated. Implement the [App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-v2) endpoint on your server to receive version 2 notifications instead.

To receive server notifications from the App Store, provide your server’s HTTPS URL in App Store Connect. Opt in to receive notifications for the production environment and the sandbox environment. For more information, see [Enabling App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/enabling-app-store-server-notifications).

Your server is responsible for parsing, interpreting, and responding to all server-to-server notification posts. For more information, see [Receiving App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/receiving-app-store-server-notifications) and [Responding to App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications).

#### Process in-app purchase notifications

Notifications cover events in the in-app purchase life cycle, including purchases, subscription renewals, offer redemptions, refunds, and more. For a complete list of notification types, see [notificationType](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype) for [App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-v2).

Use the notification type, along with the transaction and subscription renewal information, to update a customer’s service or to present promotional offers according to your business logic.

#### Process external purchase token notifications

A [notificationType](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype) of `EXTERNAL_PURCHASE_TOKEN` with an `UNREPORTED` [subtype](https://developer.apple.com/documentation/appstoreservernotifications/subtype) indicates that Apple generated an external purchase token for your app but hasn’t received a report for the token. The notification includes the token in the [externalPurchaseToken](https://developer.apple.com/documentation/appstoreservernotifications/externalpurchasetoken) field of the [responseBodyV2DecodedPayload](https://developer.apple.com/documentation/appstoreservernotifications/responsebodyv2decodedpayload). Use the token information to report it to Apple, including if you don’t recognize the token in your system. To report tokens, with or without associated transactions, call the [External Purchase Server API](https://developer.apple.com/documentation/externalpurchaseserverapi)’s [Send External Purchase Report](https://developer.apple.com/documentation/externalpurchaseserverapi/send-external-purchase-report) endpoint.

For more information about token reporting requirements in the EU, Brazil, and Japan, see [Using alternative payment options on the App Store in the European Union](https://developer.apple.com/support/apps-using-alternative-payment-providers-in-the-eu/), [Using alternative payment options on the App Store in Brazil](https://developer.apple.com/support/payment-options-on-the-app-store-in-brazil/), and [Using alternative payment options on the App Store in Japan](https://developer.apple.com/support/payment-options-on-the-app-store-in-japan/).

#### Test your server setup

To determine whether your server is receiving notifications, call the [Request a Test Notification](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification) endpoint in the [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) to ask the App Store server to send a notification with the [notificationType](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype) `TEST`. Use the `testNotificationToken` you receive to call the [Get Test Notification Status](https://developer.apple.com/documentation/appstoreserverapi/get-test-notification-status) endpoint to learn how your server responds to the test notification.

The App Store server sends the `TEST` notification in the version 2 notification format, however, it sends it to your server regardless of whether you configure a version 1 or version 2 notification URL in App Store Connect. For more information about configuring your URL in App Store Connect, see [Enter a URL for App Store server notifications](https://help.apple.com/app-store-connect/#/dev0067a330b).

## Essentials

- [Enabling App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/enabling-app-store-server-notifications) — Configure your server and provide an HTTPS URL to receive notifications about in-app purchase events and unreported external purchase tokens.

- [Receiving App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/receiving-app-store-server-notifications) — Implement server-side code to receive and parse notification posts.

- [Responding to App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications) — Send HTTP status codes to indicate the success of a notification post.

- [App Store Server Notifications changelog](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-changelog) — Learn about changes to the App Store Server Notifications service.

## Server notifications version 2

- [App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-v2) — Specify your secure server’s URL in App Store Connect to receive version 2 notifications.

- [responseBodyV2](https://developer.apple.com/documentation/appstoreservernotifications/responsebodyv2) — The response body the App Store sends in a version 2 server notification.

- [responseBodyV2DecodedPayload](https://developer.apple.com/documentation/appstoreservernotifications/responsebodyv2decodedpayload) — A decoded payload that contains the version 2 notification data.

- [notificationType](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype) — The type that describes the In-App Purchase or external purchase event for which the App Store sends the version 2 notification.

- [subtype](https://developer.apple.com/documentation/appstoreservernotifications/subtype) — A string that provides details about select notification types in version 2.

## Deprecated

- [App Store Server Notifications Version 1](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-version-1) — Receive, parse, and interpret App Store Server Notifications version 1.

## Type Aliases

- [unclaimSeatIds](https://developer.apple.com/documentation/appstoreservernotifications/unclaimseatids) — The identifiers of the seat claims that the App Store unclaimed in a group subscription that uses developer-hosted invitations.

## Related Documentation

- [Apple In-App Purchase](https://developer.apple.com/documentation/storekit/in-app-purchase) — Offer content and services in your app across Apple platforms using a Swift-based interface.

- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) — Manage your customers’ App Store transactions from your server.

- [App Store Receipts](https://developer.apple.com/documentation/appstorereceipts) — Validate app and In-App Purchase receipts with the App Store.