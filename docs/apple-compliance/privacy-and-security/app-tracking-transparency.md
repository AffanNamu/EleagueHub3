<!--
Source: https://developer.apple.com/documentation/apptrackingtransparency
Final URL: https://developer.apple.com/tutorials/data/documentation/apptrackingtransparency.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: app-tracking-transparency.json
SHA-256 of raw: 9127e8100518185319a184caba30ea9f83f7ca22ee819f783bd35f02086e0928
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# App Tracking Transparency

_Framework_

Platforms: iOS 14.0, iPadOS 14.0, Mac Catalyst 14.0, macOS 11.0, tvOS 14.0, visionOS 1.0

Request authorization to access app-related data that your app can use to track the person or the device.

### Overview

Your app needs to use the App Tracking Transparency framework if it collects data about people and shares it with other companies to track them across apps and websites. The framework presents a tracking-authorization UI and reports the current authorization status.

### Request authorization to access app-related data

To use the App Tracking Transparency framework:

1. Add the [NSUserTrackingUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsusertrackingusagedescription) key to your app’s target properties in Xcode.

2. Call [requestTrackingAuthorization(completionHandler:)](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/requesttrackingauthorization(completionhandler:)) to present the tracking-authorization request.

3. Check [trackingAuthorizationStatus](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/trackingauthorizationstatus) to determine the current authorization status; see [ATTrackingManager.AuthorizationStatus](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/authorizationstatus) for the possible values.

For more information about app tracking and privacy, see [User Privacy and Data Use](https://developer.apple.com/app-store/user-privacy-and-data-use/) and [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/).

## Essentials

- [ATTrackingManager](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager) — A class that requests tracking authorization and provides the current authorization status.

- [NSUserTrackingUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsusertrackingusagedescription) — A message that explains the purpose for accessing data that an app can use to track a person or device.

## Authorization requests

- [requestTrackingAuthorization(completionHandler:)](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/requesttrackingauthorization(completionhandler:)) — Presents a modal UI that asks someone for permission to access data that your app can use to track a person or device.

- [requestTrackingAuthorization(preferExpandedInterface:additionalInformationAction:completionHandler:)](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/requesttrackingauthorization(preferexpandedinterface:additionalinformationaction:completionhandler:)) — Presents a modal UI that asks someone for permission to access data that your app can use to track a person or device.

- [NSUserTrackingMarkdownUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsusertrackingmarkdownusagedescription) — A message that explains the purpose for accessing data that an application can use to track a person or device.

## Authorization status and results

- [trackingAuthorizationStatus](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/trackingauthorizationstatus) — A value that indicates the status of the app’s tracking authorization.

- [ATTrackingManager.AuthorizationStatus](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/authorizationstatus) — A type that represents the tracking-authorization status of an app.