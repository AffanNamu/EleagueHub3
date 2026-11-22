<!--
Source: https://developer.apple.com/help/app-review/before-submitting-for-review/test-compatible-devices
Final URL: https://developer.apple.com/help/app-review/before-submitting-for-review/test-compatible-devices
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: test-compatible-devices.html
SHA-256 of raw: 3cda0c3deab33580ab8a0bdb6cd0e36264178d08b51340d3e8dc06c41da3e684
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-review/)

### App Review Help

[App Review](/help/app-review/) / Before submitting for review / Test your app on compatible devices

Filter ⌘K

Filter ⌘K

Before submitting for review

# Test your app on compatible devices

App Review evaluates apps the way your users will use them: installed on real devices and connected to networks with real-world conditions. Users expect the app to function on all the devices where it's available. Make sure your pre-submission testing includes running the app on each device platform where it could be used, not just in simulated environments. It will also be easier to identify and resolve these issues early than if they were to occur during review.

## Use TestFlight for beta testing

[TestFlight](https://developer.apple.com/testflight/) makes it easy for testers to provide feedback after running your app on real devices:

- Add up to 100 [internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/) from your Apple Developer Program account.

- Invite up to 10,000 [external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/) by email invitation or a public link.

The first build you add to a group with external testers is sent to App Review to make sure it follows the App Review Guidelines. Later builds in the same group may not need a full review.

## Understand device compatibility

Apple platforms make it easy to distribute your app to a variety of compatible devices, so it's important to maximize your app experience on each platform you support. There are many ways an app built for one Apple device can run on other Apple devices:

- Apps designed for iPhone can run on iPad in compatibility mode if there are no dependencies on iPhone device capabilities.

- Compatible iPhone and iPad apps can run unmodified on Macs with Apple silicon.

- Compatible iPhone and iPad apps can run unmodified on Apple Vision Pro.

Xcode provides options to configure settings for apps on multiple platforms. You can specify which platforms your app's target supports in the [Supported Destinations field](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target#Configure-the-supported-destinations-for-a-target).

**Note:** People may still be able to run your app on a device even if you remove or don't include the device as a supported destination in Xcode. For example, as long as an app designed for iPhone doesn't depend on a capability that's only available on iPhone, it can be downloaded from the App Store onto iPad. Adding or removing iPad as a supported destination in Xcode won't change that app's availability on iPad.

## Follow compatibility best practices

**Plan and test for compatibility modes** so your app works on every device on which it can be downloaded.

#### Do

- Use Xcode simulators to verify basic functionality across different device types.

- Leverage [TestFlight](https://developer.apple.com/testflight/) with external testers who have access to a wide range of Apple devices.

#### Don't

- Don't submit for review without testing your app's behavior in compatibility modes.

- Don't assume removing a supported destination in Xcode prevents distribution to that device type.

**Build adaptive interfaces** that work across device variations.

#### Do

- Build interfaces that respond to different screen sizes and orientations.

- Adapt features based on available hardware, providing alternatives for a consistent experience.

#### Don't

- Don't design rigid interfaces that assume only one type of device or input method.

- Don't let your app crash or become unusable when optional hardware is unavailable.

### Restrict device distribution

Wherever possible, make your app available on multiple platforms to increase its reach and provide people with a consistent experience across devices. But there are cases where it makes sense to restrict an app's availability. For example:

- iPhone apps that rely on iPhone-specific hardware won't function as expected on iPad. Use the [UIRequiredDeviceCapabilities](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequireddevicecapabilities) key in the information property list file to specify hardware dependencies.

  Note: Apps should only use the UIRequiredDeviceCapabilities key for genuine hardware dependencies, not to indicate distribution preferences.

- Navigation- or camera-based apps are not well suited for visionOS. Learn more about [managing availability of iPhone and iPad apps on Apple Vision Pro](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-apple-vision-pro).

- Apps that rely heavily on touch inputs that can't be replicated on a keyboard are not well suited for macOS. Learn more about [restricting distribution to Apple Silicon devices](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon).

**Related** [Testing a release build](https://developer.apple.com/documentation/xcode/testing-a-release-build) [Acquiring crash reports and diagnostic logs](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs) [How to configure multiplatform apps in Xcode](https://developer.apple.com/documentation/xcode/configuring-a-multiplatform-app-target) [Configure In-App Purchases for review in the sandbox](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases)
