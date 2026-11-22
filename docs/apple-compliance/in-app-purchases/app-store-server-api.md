<!--
Source: https://developer.apple.com/documentation/appstoreserverapi
Final URL: https://developer.apple.com/tutorials/data/documentation/appstoreserverapi.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: app-store-server-api.json
SHA-256 of raw: eeda6f5dec74128c11d58a130e5e5a5bd9fc0bfce0dbfd4b5ebe95bc941f8088
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# App Store Server API

_Web Service_

Platforms: App Store Server API 1.0

Manage your customers’ App Store transactions from your server.

### Overview

The App Store Server API is a REST API that you call from your server to request and provide information about your customers’ In-App Purchases. The App Store signs the transaction and subscription renewal information that this API returns using the [JSON Web Signature (JWS)](https://datatracker.ietf.org/doc/html/rfc7515) specification. Most endpoints return data for a single customer of your app, indicated by a transaction identifier that you provide.

The App Store Server API is independent of the app’s installation status on the customers’ devices. The App Store server returns information based on a customer’s In-App Purchase history regardless of whether the customer installs, removes, or reinstalls the app on their devices.

This API provides the following functionality:

- **Transactions and auto-renewable subscription status.** Get information for single transactions by calling [Get Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info) or a customer’s entire transaction history using [Get Transaction History](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-history). Call [Get All Subscription Statuses](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses) for up-to-date subscription status. Use this information to keep your customers’ purchase information current on your server.

- **Refund information.** Call [Get Refund History](https://developer.apple.com/documentation/appstoreserverapi/get-refund-history) to get a customer’s refund history. Use the [Send Consumption Information](https://developer.apple.com/documentation/appstoreserverapi/send-consumption-information) endpoint to send information to the App Store when customers request a refund for an In-App Purchase, after you receive the `CONSUMPTION_REQUEST` [notificationType](https://developer.apple.com/documentation/appstoreservernotifications/notificationtype) from [App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-v2). Your data helps inform refund decisions.

- **App Store Server Notifications history and testing.** Call [Get Notification History](https://developer.apple.com/documentation/appstoreserverapi/get-notification-history) to request the notifications your server may have missed in the past 180 days (or 30 days in the sandbox environment). Call [Request a Test Notification](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification) and [Get Test Notification Status](https://developer.apple.com/documentation/appstoreserverapi/get-test-notification-status) to test if your server is successfully receiving notifications at its [App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-v2) endpoint.

- **Subscription renewal date extensions.** Call [Extend a Subscription Renewal Date](https://developer.apple.com/documentation/appstoreserverapi/extend-a-subscription-renewal-date) and related endpoints to compensate your customers for temporary service outages, canceled events, or interruptions to live-streamed events by extending the renewal date of their paid, active subscription. For more information, see [Extending the renewal date for auto-renewable subscriptions](https://developer.apple.com/documentation/appstoreserverapi/extending-the-renewal-date-for-auto-renewable-subscriptions).

- **Order information lookup.** Call [Look Up Order ID](https://developer.apple.com/documentation/appstoreserverapi/look-up-order-id) to get In-App Purchase information based on a customer’s order ID, found on the App Store receipt that customers receive in email.

- **App transaction information and setting an app account token.** Call [Get App Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-app-transaction-info) to get details about the customer’s purchase of your app, such as the original purchase date and version. Use [Set App Account Token](https://developer.apple.com/documentation/appstoreserverapi/set-app-account-token) to set an app account token when your customer makes an In-App Purchase outside your app, or to update its value.

- **Multiseat purchases.** Call [Get Customer Groups](https://developer.apple.com/documentation/appstoreserverapi/get-customer-groups) to find out whether a customer has access to your app through an organization or group, and what role they hold. Call [Get Group Members](https://developer.apple.com/documentation/appstoreserverapi/get-group-members) to list that group’s members. In the production environment, these endpoints support only groups with a [groupType](https://developer.apple.com/documentation/appstoreserverapi/grouptype) of `ORGANIZATION`.

Your server must support the Transport Layer Security (TLS) protocol 1.2 or later to use the App Store Server API.

Check the [App Store Server API changelog](https://developer.apple.com/documentation/appstoreserverapi/app-store-server-api-changelog) to learn about the latest changes to this API. Look for videos about the App Store Server API on the [Apple Developer website](https://developer.apple.com/videos/all-videos/?q=%22App%20Store%20Server%20API%22).

#### Authorize your API calls

Calls to the API require JSON Web Tokens (JWTs) for authorization; you obtain keys to create the tokens from your organization’s App Store Connect account. See [Creating API keys to authorize API requests](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests) to create your keys. See [Generating JSON Web Tokens for API requests](https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests) to generate tokens using your keys, and send API requests.

After you have a complete and signed token, provide the token in the request’s authorization header as a bearer token. Generate a new token for each new API request, or reuse tokens until they expire.

#### Create JWTs, verify transactions, and more using the App Store Server Library

The App Store Server Library is an open source library from Apple, available in four languages. It provides a client that make it easier to adopt the App Store Server APIs, including creating the JWTs to authorize calls. For more information, see [Simplifying your implementation by using the App Store Server Library](https://developer.apple.com/documentation/appstoreserverapi/simplifying-your-implementation-by-using-the-app-store-server-library) and the WWDC23 session [Meet the App Store Server Library](https://developer.apple.com/videos/play/wwdc2023/10143/).

#### Test using the sandbox environment

All App Store Server API endpoints are available for testing in the sandbox environment, except [Look Up Order ID](https://developer.apple.com/documentation/appstoreserverapi/look-up-order-id). Access the sandbox environment by sending requests to the endpoints using the following base URL:

```other
https://api.storekit-sandbox.apple.com/
```

For example, to call [Get Transaction History](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-history) in the sandbox environment, send a request using the sandbox URL:

```other
https://api.storekit-sandbox.apple.com/inApps/v2/history/{anyTransactionId}
```

Note that `/inApps` in the path is case-sensitive.

For endpoints that take a [transactionId](https://developer.apple.com/documentation/appstoreserverapi/transactionid) as a parameter, be sure to call the endpoint using the same environment that creates the transaction identifier. Environment information is present in the [environment](https://developer.apple.com/documentation/appstoreserverapi/environment) property of the [JWSTransactionDecodedPayload](https://developer.apple.com/documentation/appstoreserverapi/jwstransactiondecodedpayload).

If you don’t have environment information, follow these steps:

1. Call the endpoint using the production URL. If the call succeeds, the transaction identifier belongs to the production environment.

2. If you receive an error code `4040010` [TransactionIdNotFoundError](https://developer.apple.com/documentation/appstoreserverapi/transactionidnotfounderror), call the endpoint using the sandbox environment.

3. If the call succeeds, the transaction identifier belongs to the sandbox environment. If the call fails with the `4040010` error code, the transaction identifier isn’t present in either environment.

## Essentials

- [Simplifying your implementation by using the App Store Server Library](https://developer.apple.com/documentation/appstoreserverapi/simplifying-your-implementation-by-using-the-app-store-server-library) — Use Apple’s open source library to create JSON Web Tokens (JWT) to authorize your calls, verify transactions, extract transaction identifiers from receipts, and more.

- [Creating API keys to authorize API requests](https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests) — Create API keys you use to sign JSON Web Tokens and authorize API requests.

- [Generating JSON Web Tokens for API requests](https://developer.apple.com/documentation/appstoreserverapi/generating-json-web-tokens-for-api-requests) — Create JSON Web Tokens signed with your private key to authorize requests for App Store Server API and External Purchase Server API.

- [Identifying rate limits](https://developer.apple.com/documentation/appstoreserverapi/identifying-rate-limits) — Recognize the rate limits that apply to App Store Server API endpoints and handle them in your code.

- [App Store Server API changelog](https://developer.apple.com/documentation/appstoreserverapi/app-store-server-api-changelog) — Learn about new features and updates in the App Store Server API.

## In-App Purchase history

- [Get Transaction History](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-history) — Get a customer’s in-app purchase transaction history for your app.

- [HistoryResponse](https://developer.apple.com/documentation/appstoreserverapi/historyresponse) — A response that contains the customer’s transaction history for an app.

## Transaction information

- [Get Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info) — Get information about a single transaction for your app.

- [TransactionInfoResponse](https://developer.apple.com/documentation/appstoreserverapi/transactioninforesponse) — A response that contains signed transaction information for a single transaction.

## App Transaction information

- [Get App Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-app-transaction-info) — Get a customer’s app transaction information for your app.

- [AppTransactionInfoResponse](https://developer.apple.com/documentation/appstoreserverapi/apptransactioninforesponse) — A response that contains signed app transaction information for a customer.

## Subscription status

- [Get All Subscription Statuses](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses) — Get the statuses for all of a customer’s auto-renewable subscriptions in your app.

- [StatusResponse](https://developer.apple.com/documentation/appstoreserverapi/statusresponse) — A response that contains status information for all of a customer’s auto-renewable subscriptions in your app.

## Multiseat purchases

- [Get Customer Groups](https://developer.apple.com/documentation/appstoreserverapi/get-customer-groups) — Get the groups that a customer belongs to, and their role in each group.

- [GetCustomerGroupsResponse](https://developer.apple.com/documentation/appstoreserverapi/getcustomergroupsresponse) — A response that contains the groups a customer belongs to, and their role in each group.

- [Get Group Members](https://developer.apple.com/documentation/appstoreserverapi/get-group-members) — Get a paginated list of the customers that belong to a group.

- [GetGroupMembersResponse](https://developer.apple.com/documentation/appstoreserverapi/getgroupmembersresponse) — A response that contains a page of the customers that belong to a group.

## Seat management

- [Get Seat Info](https://developer.apple.com/documentation/appstoreserverapi/get-seat-info) — Get the seat counts and the seat claims of a group subscription that uses developer-hosted invitations.

- [GetSeatInfoResponse](https://developer.apple.com/documentation/appstoreserverapi/getseatinforesponse) — A response that contains the seat counts and the seat claims of a group subscription that uses developer-hosted invitations.

- [Claim Seat](https://developer.apple.com/documentation/appstoreserverapi/claim-seat) — Claim a seat for a customer in a group subscription that uses developer-hosted invitations.

- [ClaimSeatRequest](https://developer.apple.com/documentation/appstoreserverapi/claimseatrequest) — The request body that contains the information to claim a seat in a group subscription that uses developer-hosted invitations.

- [ClaimSeatResponse](https://developer.apple.com/documentation/appstoreserverapi/claimseatresponse) — A response that contains the identifier of a seat claim.

- [Unclaim Seat](https://developer.apple.com/documentation/appstoreserverapi/unclaim-seat) — Release a claimed seat in a group subscription that uses developer-hosted invitations.

- [Associate Seat](https://developer.apple.com/documentation/appstoreserverapi/associate-seat) — Associate a customer with a claimed seat in a group subscription that uses developer-hosted invitations.

- [AssociateSeatRequest](https://developer.apple.com/documentation/appstoreserverapi/associateseatrequest) — The request body that contains the app transaction identifier of the customer who occupies a claimed seat.

## App Account Token

- [Set App Account Token](https://developer.apple.com/documentation/appstoreserverapi/set-app-account-token) — Sets the app account token value for a purchase the customer makes outside of your app, or updates its value in an existing transaction.

- [UpdateAppAccountTokenRequest](https://developer.apple.com/documentation/appstoreserverapi/updateappaccounttokenrequest) — The request body that contains an app account token value.

## Order ID lookup

- [Look Up Order ID](https://developer.apple.com/documentation/appstoreserverapi/look-up-order-id) — Get a customer’s in-app purchases from a receipt using the order ID.

- [orderId](https://developer.apple.com/documentation/appstoreserverapi/orderid) — The customer’s order ID from an App Store receipt for in-app purchases.

- [OrderLookupResponse](https://developer.apple.com/documentation/appstoreserverapi/orderlookupresponse) — A response that includes the order lookup status and an array of signed transactions for the in-app purchases in the order.

## Finishing transactions

- [Finish Transaction](https://developer.apple.com/documentation/appstoreserverapi/finish-transaction) — Notifies the App Store server that your system has finished processing the customer’s transaction.

## Consumption information

- [Send Consumption Information](https://developer.apple.com/documentation/appstoreserverapi/send-consumption-information) — Send consumption information about an In-App Purchase to the App Store after your server receives a consumption request notification.

- [ConsumptionRequest](https://developer.apple.com/documentation/appstoreserverapi/consumptionrequest) — The request body that contains consumption information for an In-App Purchase.

- [Send Consumption Information V1](https://developer.apple.com/documentation/appstoreserverapi/send-consumption-information-v1) — Send consumption information about a consumable In-App Purchase or auto-renewable subscription to the App Store after your server receives a consumption request notification.

- [ConsumptionRequestV1](https://developer.apple.com/documentation/appstoreserverapi/consumptionrequestv1) — The request body containing consumption information.

## Refund lookup

- [Get Refund History](https://developer.apple.com/documentation/appstoreserverapi/get-refund-history) — Get a paginated list of all of a customer’s refunded in-app purchases for your app.

- [RefundHistoryResponse](https://developer.apple.com/documentation/appstoreserverapi/refundhistoryresponse) — A response that contains an array of signed JSON Web Signature (JWS) refunded transactions, and paging information.

## Subscription-renewal-date extension

- [Extending the renewal date for auto-renewable subscriptions](https://developer.apple.com/documentation/appstoreserverapi/extending-the-renewal-date-for-auto-renewable-subscriptions) — Compensate eligible active subscribers for service interruptions by extending a subscription’s renewal date.

- [Extend a Subscription Renewal Date](https://developer.apple.com/documentation/appstoreserverapi/extend-a-subscription-renewal-date) — Extends the renewal date of a customer’s active subscription using the original transaction identifier.

- [Extend Subscription Renewal Dates for All Active Subscribers](https://developer.apple.com/documentation/appstoreserverapi/extend-subscription-renewal-dates-for-all-active-subscribers) — Uses a subscription’s product identifier to extend the renewal date for all of its eligible active subscribers.

- [Get Status of Subscription Renewal Date Extensions](https://developer.apple.com/documentation/appstoreserverapi/get-status-of-subscription-renewal-date-extensions) — Checks whether a renewal date extension request completed, and provides the final count of successful or failed extensions.

- [ExtendRenewalDateRequest](https://developer.apple.com/documentation/appstoreserverapi/extendrenewaldaterequest) — The request body that contains subscription-renewal-extension data for an individual subscription.

- [ExtendRenewalDateResponse](https://developer.apple.com/documentation/appstoreserverapi/extendrenewaldateresponse) — A response that indicates whether an individual renewal-date extension succeeded, and related details.

- [MassExtendRenewalDateRequest](https://developer.apple.com/documentation/appstoreserverapi/massextendrenewaldaterequest) — The request body that contains subscription-renewal-extension data to apply for all eligible active subscribers.

- [MassExtendRenewalDateResponse](https://developer.apple.com/documentation/appstoreserverapi/massextendrenewaldateresponse) — A response that indicates the server successfully received the subscription-renewal-date extension request.

- [MassExtendRenewalDateStatusResponse](https://developer.apple.com/documentation/appstoreserverapi/massextendrenewaldatestatusresponse) — A response that indicates the current status of a request to extend the subscription renewal date to all eligible subscribers.

## App Store Server Notifications history

- [Get Notification History](https://developer.apple.com/documentation/appstoreserverapi/get-notification-history) — Get a list of notifications that the App Store server attempted to send to your server.

- [NotificationHistoryRequest](https://developer.apple.com/documentation/appstoreserverapi/notificationhistoryrequest) — The request body for notification history.

- [NotificationHistoryResponse](https://developer.apple.com/documentation/appstoreserverapi/notificationhistoryresponse) — A response that contains the App Store Server Notifications history for your app.

- [notificationHistoryResponseItem](https://developer.apple.com/documentation/appstoreserverapi/notificationhistoryresponseitem) — The App Store server notification history record, including the signed notification payload and the result of the server’s first send attempt.

## App Store Server Notifications testing

- [Request a Test Notification](https://developer.apple.com/documentation/appstoreserverapi/request-a-test-notification) — Ask App Store Server Notifications to send a test notification to your server.

- [Get Test Notification Status](https://developer.apple.com/documentation/appstoreserverapi/get-test-notification-status) — Check the status of the test App Store server notification sent to your server.

- [SendTestNotificationResponse](https://developer.apple.com/documentation/appstoreserverapi/sendtestnotificationresponse) — A response that contains the test notification token.

- [CheckTestNotificationResponse](https://developer.apple.com/documentation/appstoreserverapi/checktestnotificationresponse) — A response that contains the contents of the App Store server’s test notification and the result from your server.

## JWS headers and payloads

- [JWSDecodedHeader](https://developer.apple.com/documentation/appstoreserverapi/jwsdecodedheader) — A decoded JSON Web Signature (JWS) header containing transaction or renewal information.

- [JWSAppTransaction](https://developer.apple.com/documentation/appstoreserverapi/jwsapptransaction) — App transaction information signed by the App Store, in JSON Web Signature (JWS) Compact Serialization format.

- [JWSAppTransactionDecodedPayload](https://developer.apple.com/documentation/appstoreserverapi/jwsapptransactiondecodedpayload) — A decoded payload that contains app transaction information.

- [JWSTransaction](https://developer.apple.com/documentation/appstoreserverapi/jwstransaction) — Transaction information signed by the App Store, in JSON Web Signature (JWS) Compact Serialization format.

- [JWSTransactionDecodedPayload](https://developer.apple.com/documentation/appstoreserverapi/jwstransactiondecodedpayload) — A decoded payload that contains transaction information.

- [JWSRenewalInfo](https://developer.apple.com/documentation/appstoreserverapi/jwsrenewalinfo) — Subscription renewal information, signed by the App Store, in JSON Web Signature (JWS) format.

- [JWSRenewalInfoDecodedPayload](https://developer.apple.com/documentation/appstoreserverapi/jwsrenewalinfodecodedpayload) — A decoded payload containing subscription renewal information for an auto-renewable subscription.

- [Data types](https://developer.apple.com/documentation/appstoreserverapi/data-types) — Refer to these data types for decoded transaction and renewal information payloads.

## Error information

- [Error codes](https://developer.apple.com/documentation/appstoreserverapi/error-codes) — Understand the error codes that App Store Server API responses return.

## Deprecated

- [Get Transaction History V1](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-history-v1) — Get a customer’s in-app purchase transaction history for your app, except finished consumable in-app purchases.

- [Get Refund History V1](https://developer.apple.com/documentation/appstoreserverapi/get-refund-history-v1) — Get a list of up to 50 of a customer’s refunded in-app purchases for your app.

- [RefundLookupResponse](https://developer.apple.com/documentation/appstoreserverapi/refundlookupresponse) — A response that contains an array of signed JSON Web Signature (JWS) transactions.

## Dictionaries

- [advancedCommerceBundleItem](https://developer.apple.com/documentation/appstoreserverapi/advancedcommercebundleitem) — 

## Type Aliases

- [previousOriginalTransactionId](https://developer.apple.com/documentation/appstoreserverapi/previousoriginaltransactionid) — The original transaction identifier of a subscription before migration.