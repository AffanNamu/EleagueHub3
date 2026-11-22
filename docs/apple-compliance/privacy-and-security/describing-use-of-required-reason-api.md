<!--
Source: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
Final URL: https://developer.apple.com/tutorials/data/documentation/bundleresources/describing-use-of-required-reason-api.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: describing-use-of-required-reason-api.json
SHA-256 of raw: d49be095f6898f0b441e395c2b4ff9f8b4227afdfbe77046208868ae7108a1cd
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# Describing use of required reason API

_Article_

Ensure your use of covered API is consistent with policy.

### Overview

Some APIs that your app uses to deliver its core functionality — in code you write or included in a third-party SDK — have the potential of being misused to access device signals to try to identify the device or user, also known as fingerprinting. Regardless of whether a user gives your app permission to track, fingerprinting is not allowed. Describe the reasons your app or third-party SDK on iOS, iPadOS, tvOS, visionOS, or watchOS uses these APIs, and check that your app or third-party SDK only uses the APIs for the expected reasons.

> **Important:** If you upload an app to App Store Connect that uses required reason API without describing the reason in its privacy manifest file, Apple sends you an email reminding you to add the reason to the app’s privacy manifest. Starting May 1, 2024, apps that don’t describe their use of required reason API in their privacy manifest file aren’t accepted by App Store Connect.

For each category of required reason API that your app or third-party SDK uses, add a dictionary to the [NSPrivacyAccessedAPITypes](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes) array in your app or third-party SDK’s privacy manifest file that reports the reasons your app uses the API category. If you use the API in your app’s code, then you need to report the API in your app’s privacy manifest file. If you use the API in your third-party SDK’s code, then you need to report the API in your third-party SDK’s privacy manifest file. Your third-party SDK can’t rely on the privacy manifest files for apps that link the third-party SDK, or those of other third-party SDKs the app links, to report your third-party SDK’s use of required reasons API.

For each executable or dynamic library in an app that uses a required reason API, the bundle that includes the executable or dynamic library needs to include a privacy manifest file that reports the API. For the expected location of frameworks and dynamic libraries, see [Placing content in a bundle](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle).

> **Important:** Your app or third-party SDK must declare one or more approved reasons that accurately reflect your use of each of these APIs and the data derived from their use. You may use these APIs and the data derived from their use for the declared reasons only. These declared reasons must be consistent with your app’s functionality as presented to users, and you may not use the APIs or derived data for tracking.

Each dictionary in the `NSPrivacyAccessedAPITypes` array needs to contain these keys and values:

- **[NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)**: A string that identifies the category of required reason APIs your app uses. The value you provide must be one of the values listed in the sections below.

- **[NSPrivacyAccessedAPITypeReasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)**: An array of strings that identifies the reasons your app uses the APIs. The values you provide must be the values associated with the accessed API type in the sections below.

The categories of required reason APIs, which APIs are in each category, and the reasons you can include in a privacy manifest are described in the documentation for the dictionary keys.

> **Note:** Apple continually reviews the list of required reason APIs and reasons for usage, and will update this article from time to time. If your app uses required reason API to provide benefits to the people using the app, for a reason that isn’t listed here, [submit a request for a new approved reason](https://developer.apple.com/contact/request/privacy-manifest-reason/).

For more information on creating a privacy manifest file, see [Create a privacy manifest](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files#Create-a-privacy-manifest).

## Essentials

- [Adding a privacy manifest to your app or third-party SDK](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk) — Report the data you collect and the required reasons API you use in your app or third-party SDK.

- [Describing data use in privacy manifests](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests) — Declare the data collected by your app or by third-party SDKs.

- [Editing property list files](https://developer.apple.com/documentation/xcode/editing-property-list-files) — Add, remove, and change keys and values in a structured file.

- [App Privacy Configuration](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration) — A data structure that represents the root object in a privacy manifest file.