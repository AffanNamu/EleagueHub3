<!--
Source: https://developer.apple.com/documentation/bundleresources/information-property-list/nsusertrackingusagedescription
Final URL: https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/nsusertrackingusagedescription.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: nsusertrackingusagedescription.json
SHA-256 of raw: bf6c461eaec00954533fc1181f64dce116e87b36300b04fbd7984d3337e6e1a4
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# NSUserTrackingUsageDescription

_Property List Key_

Platforms: iOS 14.0, iPadOS 14.0, tvOS 14.0, visionOS 1.0

A message that explains the purpose for accessing data that an app can use to track a person or device.

### Discussion

If your application uses the [App Tracking Transparency](https://developer.apple.com/documentation/apptrackingtransparency) framework, you need to provide a *usage-description string* to explain the purpose for accessing app-related data that the app can use to track a person or device. The system displays the string in a modal UI from which the person can grant or deny permission to access the tracking data.

This key is required. Your app crashes if it attempts to use the [App Tracking Transparency](https://developer.apple.com/documentation/apptrackingtransparency) framework without including the key in your target’s properties in Xcode.

The system displays this key’s string in a modal UI when your app requests authorization to access app-related data that the app can use to track the person or the device by calling either method:

- [requestTrackingAuthorization(completionHandler:)](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/requesttrackingauthorization(completionhandler:))

- [requestTrackingAuthorization(preferExpandedInterface:additionalInformationAction:completionHandler:)](https://developer.apple.com/documentation/apptrackingtransparency/attrackingmanager/requesttrackingauthorization(preferexpandedinterface:additionalinformationaction:completionhandler:))

> **Important:** Alternatively, in the European Union, your app can provide a tracking-usage description that supports rich text elements by using markdown format (see [NSUserTrackingMarkdownUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsusertrackingmarkdownusagedescription)).

Keep the text of your description short and specific. The system displays your app name in the prompt, so you don’t need to include it in the string. For example usage descriptions, see [Apple’s Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/ios/app-architecture/accessing-user-data/).

## Security

- [NSUpdateSecurityPolicy](https://developer.apple.com/documentation/bundleresources/information-property-list/nsupdatesecuritypolicy) — A dictionary that identifies which apps or installer packages the operating system allows to write to the app’s bundle.

- [NSAppBundlesUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappbundlesusagedescription) — A message that tells people why the app needs to access the contents of other apps’ bundles.

- [NSAppDataUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappdatausagedescription) — A message that tells people why the app needs to access files in other apps’ sandbox containers.

- [NSUserTrackingMarkdownUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsusertrackingmarkdownusagedescription) — A message that explains the purpose for accessing data that an application can use to track a person or device.

- [NSAppleEventsUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription) — A message that tells people why the app is requesting the ability to send Apple events.

- [NSSystemAdministrationUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nssystemadministrationusagedescription) — A message in macOS that tells people why the app is requesting to manipulate the system configuration.

- [ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption) — A Boolean value indicating whether the app uses encryption.

- [ITSEncryptionExportComplianceCode](https://developer.apple.com/documentation/bundleresources/information-property-list/itsencryptionexportcompliancecode) — The export compliance code provided by App Store Connect for apps that require it.