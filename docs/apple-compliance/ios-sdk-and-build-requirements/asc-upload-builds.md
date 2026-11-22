<!--
Source: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
Final URL: https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: asc-upload-builds.html
SHA-256 of raw: a91e545d14528c2cc2d9853295066069a1ea80fcda5f1d08e4144b08c46c0d74
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Manage builds / Upload builds

Filter ⌘K

Filter ⌘K

Manage builds

# Upload builds

**Required role:** Account Holder, Admin, App Manager, or Developer. [View role permissions.](/help/app-store-connect/reference/account-management/role-permissions)

After [adding an app to your account](/help/app-store-connect/create-an-app-record/add-a-new-app), you can upload a build using Xcode, Swift Playground, altool, or Transporter. If you use the [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi), you might want to upload your binary using the Transporter command-line tool and JSON Web Tokens (JWTs) for authentication. You can use the same JWTs that you use for the API to upload your binary. As your app changes, you can upload more builds, [distribute a build for testing](/help/app-store-connect/test-a-beta-version/testflight-overview), or [submit your app for review](/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review).

The first time you upload a build, a beta version of the app is created in your account. However, the build needs to be processed in Apple’s system before it appears in App Store Connect. You’ll receive an email when this process is complete.

Each time you upload a build, the bundle ID and version number, which are located in the app bundle, are used to associate the build with the app and version record in App Store Connect. The build string is used to uniquely identify the build throughout the system.

You can also create and upload your build using Xcode Cloud. Xcode Cloud lets you adopt continuous integration and continuous delivery (CI/CD), a standard practice that helps monitor and improve software quality over time, ensuring your app or framework is always in a releasable state. [Learn more about Xcode Cloud](https://developer.apple.com/documentation/xcode/xcode-cloud).

You also have the option to upload assets that are managed separately from a build by using Apple-Hosted Background Assets. [Learn more.](/help/app-store-connect/manage-asset-packs/overview-of-apple-hosted-asset-packs%20)

[Learn about upcoming upload requirements.](/news/upcoming-requirements/)

## Upload your app binary files with Xcode

Xcode is Apple’s integrated development environment (IDE). You use Xcode to build apps for Apple products, including iPhone, iPad, Mac, Apple TV, Apple Vision Pro, and Apple Watch. Xcode provides tools to manage your entire development workflow—from creating your app to testing, optimizing, and submitting it for review.

To learn how to upload your app binary using Xcode, visit [Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), or in Xcode, choose Help \> Xcode Help and search for “Distributing your app for beta testing and releases.”

[Download Xcode](https://apps.apple.com/us/app/xcode/id497799835?mt=12) on the Mac App Store.

### Supported Xcode Versions

App Store Connect supports the following versions of Xcode to upload your app for customer distribution or to testers using TestFlight. You can view delivery progress, including warnings, errors, and delivery logs, as well as a history of past deliveries.

[TABLE]

Upload for all target types is supported for Transporter and altool.

### Upload your app binary files with the App Store Connect API

The App Store Connect API is a REST API that enables the automation of actions you take in App Store Connect.

Calls to the API require JSON Web Tokens (JWT) for authorization; you obtain keys to create the tokens from your organization’s App Store Connect account. [Learn how to create API keys to sign JWT.](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api)

You can upload your app binary with the App Store Connect API. [Learn more.](https://developer.apple.com/documentation/appstoreconnectapi/post-v1-builduploads)

### Upload your app binary files with altool

You can use `xcrun`, included with Xcode, to invoke altool, a command-line tool that lets you validate and upload your app binary files to App Store Connect. Specify one of the following in Terminal at the command-line:

`$ xcrun altool --validate-app -f file -t platform -u username [-p password] [--output-format xml]`  
`$ xcrun altool --upload-app -f file -t platform -u username [-p password] [--output-format xml]`

[Learn more about using altool.](https://help.apple.com/asc/appsaltool/)

### Upload your app binary files with Transporter

Transporter is a macOS app that provides a simple and easy way to upload an app to App Store Connect for distribution. You can view delivery progress including warnings, errors, delivery logs, and a history of past deliveries.

You can download the latest version of Transporter [on the Mac App Store.](https://apps.apple.com/us/app/transporter/id1450874784?mt=12)

[Learn more about Transporter Help.](https://help.apple.com/itc/transporter/)

**Related** [View builds and metadata](/help/app-store-connect/manage-builds/view-builds-and-metadata) [Choose a build to submit](/help/app-store-connect/manage-builds/choose-a-build-to-submit) [Maximum build file sizes](/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes) [App build statuses](/help/app-store-connect/reference/app-uploads/app-build-statuses) [TN3147: Migrating to the latest notarization tool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)
