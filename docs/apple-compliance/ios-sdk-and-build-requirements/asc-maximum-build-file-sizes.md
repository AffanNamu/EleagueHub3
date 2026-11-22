<!--
Source: https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes
Final URL: https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: asc-maximum-build-file-sizes.html
SHA-256 of raw: 0cc0be799d070fa96b5621706d87bf99a6f8ddc8f527c79e4f98df57b109018d
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-store-connect/)

### App Store Connect Help

[App Store Connect](/help/app-store-connect/) / Reference / [App uploads](/help/app-store-connect/reference/app-uploads/) / Maximum build file sizes

Filter ⌘K

Filter ⌘K

Reference

# Maximum build file sizes

Verify that your app, along with each Mach-O executable file (for example, `app_name.app/app_name`), doesn’t exceed the maximum file size limits on the supported operating systems.

For iOS, iPadOS, macOS, tvOS, and visionOS apps, you can use [Background Assets](https://developer.apple.com/documentation/backgroundassets) to host larger assets that are managed separately from your build.

The size shown on your App Store product page varies depending on the device that’s viewing the page. On macOS, the product page shows the the universal installation size. On all other platforms, it shows the installation size for the specific device model. If your app uses [Apple-Hosted Background Assets](/help/app-store-connect/manage-asset-packs/overview-of-apple-hosted-asset-packs), the product page shows an “Up to” size that also includes any non-localized essential asset packs and the localized essential asset packs for the single language with the largest total size.

[Learn how to view the file sizes of an uploaded build.](/help/app-store-connect/manage-builds/view-builds-and-metadata#view-the-file-sizes-of-a-build)

[TABLE]

¹ For the total of all *\_\_TEXT* sections in the binary.

² For the *\_\_TEXT* sections in each architecture slice. An architecture slice is a part of the fat binary layout that targets a specific architecture. For example, a fat binary might include slices for 32-bit and 64-bit architectures.

## App Clips

To ensure a successful launch experience, verify that the uncompressed main bundle of any App Clip variant, after app thinning, doesn’t exceed the maximum size limit for the minimum deployment target used in the App Clip.

[Learn how to measure the size of your App Clip.](https://developer.apple.com/documentation/appclip/creating-an-app-clip-with-xcode#Keep-your-App-Clip-small-in-size)

[TABLE]

**Related** [Add testers to builds](/help/app-store-connect/test-a-beta-version/add-testers-to-builds) [Upload builds](/help/app-store-connect/manage-builds/upload-builds) [What is app thinning? (iOS, tvOS, watchOS)](https://help.apple.com/xcode/mac/current/#/devbbdc5ce4f) [Gathering information about memory use](https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use) [Reducing your app’s size](https://developer.apple.com/documentation/xcode/reducing-your-app-s-size)
