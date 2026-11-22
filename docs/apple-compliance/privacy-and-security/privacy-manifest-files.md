<!--
Source: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
Final URL: https://developer.apple.com/tutorials/data/documentation/bundleresources/privacy-manifest-files.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: privacy-manifest-files.json
SHA-256 of raw: ac4729cabb8088dae110896ee0be586fbf8dc9c42bf21408a908bb26e8823444
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# Privacy manifest files

_API Collection_

Describe the data your app or third-party SDK collects and the required reasons APIs it uses.

### Overview

Apps and third-party SDKs — distributed as XCFrameworks, Swift packages, or Xcode projects — can contain a privacy manifest file, named `PrivacyInfo.xcprivacy`. The privacy manifest is a property list that records the following information:

- The types of data collected by your app or third-party SDK. You need to provide this information for your app or third-party SDK on all platforms.

- The required reasons APIs your app or third-party SDK uses. You need to provide this information for your app or third-party SDK on iOS, iPadOS, tvOS, visionOS, and watchOS.

For each type of data your app or third-party SDK collects and category of required reasons API it uses, the app or third-party SDK needs to record the reasons in its bundled privacy manifest file.

> **Important:** You need to include a privacy manifest file in your third-party SDK if it’s listed in “SDKs that require a privacy manifest and signature,” in [Upcoming third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/). Otherwise, include a privacy manifest file in your third-party SDK if it uses a required reasons API, collects data about the person using apps that include the third-party SDK, enables the app to collect data about people using the app, or contacts tracking domains. Providing a privacy manifest file helps app developers understand the API use and data-collection practices of your third-party SDK.

For information on editing the privacy manifest file, see [Editing property list files](https://developer.apple.com/documentation/xcode/editing-property-list-files).

#### Create a privacy manifest

To add the privacy manifest to your app or third-party SDK in Xcode, follow these steps:

- Choose File > New File.

- Scroll down to the Resource section, and select App Privacy File type.

- Click Next.

- Check your app or third-party SDK’s target in the Targets list.

- Click Create.

By default, the file is named `PrivacyInfo.xcprivacy`; this is the required file name for bundled privacy manifests.

> **Note:** You need to add the privacy manifest file to your target’s resources for Xcode to use it when you generate a privacy report. If you distribute your third-party SDK as a static library, use the support for static frameworks in Xcode 15 or later to bundle resources, including the privacy manifest file. Create a framework target in Xcode that builds your product, set its Mach-O type build setting to “Static Library,” and add the privacy manifest file to your target’s bundle resources along with any other resources, for example, image files.

At the top level of this property list file, add the following keys to the dictionary:

- **[NSPrivacyTracking](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacytracking)**: A Boolean that indicates whether your app or third-party SDK uses data for tracking as defined under the App Tracking Transparency framework. When set to `true` you need to provide a list of internet domains in `NSPrivacyTrackingDomains`. For more information, see [User Privacy and Data Use](https://developer.apple.com/app-store/user-privacy-and-data-use/).

- **[NSPrivacyTrackingDomains](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacytrackingdomains)**: An array of strings that lists the internet domains your app or third-party SDK connects to that engage in tracking. If the user has not granted tracking permission through the App Tracking Transparency framework, network requests to these domains fail and your app receives an error. To provide a list of internet domains in `NSPrivacyTrackingDomains`, set `NSPrivacyTracking` to `true`.

- **[NSPrivacyCollectedDataTypes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacycollecteddatatypes)**: An array of dictionaries that describes the data types your app or third-party SDK collects. For information on the keys and values to use in the dictionaries, see [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests).

- **[NSPrivacyAccessedAPITypes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes)**: An array of dictionaries that describe the API types your app or third-party SDK accesses that have been designated as APIs that require reasons to access. For information on the keys and values to use in the dictionaries, see [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api).

## Essentials

- [Adding a privacy manifest to your app or third-party SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) — Report the data you collect and the required reasons API you use in your app or third-party SDK.

- [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests) — Declare the data collected by your app or by third-party SDKs.

- [Describing use of required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) — Ensure your use of covered API is consistent with policy.

- [Editing property list files](https://developer.apple.com/documentation/xcode/editing-property-list-files) — Add, remove, and change keys and values in a structured file.

- [App Privacy Configuration](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration) — A data structure that represents the root object in a privacy manifest file.

## Property Lists

- [Entitlements](https://developer.apple.com/documentation/bundleresources/entitlements) — Key-value pairs that grant an executable permission to use a service or technology.

- [Information Property List](https://developer.apple.com/documentation/bundleresources/information-property-list) — A resource containing key-value pairs that identify and configure a bundle.