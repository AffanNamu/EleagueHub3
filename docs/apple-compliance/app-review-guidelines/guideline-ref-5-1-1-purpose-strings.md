<!--
Source: https://developer.apple.com/help/app-review/guideline-reference/5-1-1-purpose-strings
Final URL: https://developer.apple.com/help/app-review/guideline-reference/5-1-1-purpose-strings
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: guideline-ref-5-1-1-purpose-strings.html
SHA-256 of raw: 5bf407e34b3be92e1441707d752f7e8b5995cd6f7207366f8db817418efcc17f
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

[](/help/app-review/)

### App Review Help

[App Review](/help/app-review/) / Guideline reference / 5.1.1(ii) - Write clear purpose strings

Filter ⌘K

Filter ⌘K

Guideline reference

# 5.1.1(ii) - Write clear purpose strings

Apple operating systems restrict access to protected data and resources by default, so before your app can access resources like the camera, location, microphone, or health data, it has to request permission. These requests often include a purpose string, also called a usage description, that explains how your app will use the requested data or resource.

[App Review Guideline 5.1.1(ii)](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) specifies requirements for purpose strings:

> **5.1.1(ii) Permission**
>
> \[...\] Ensure your purpose strings clearly and completely describe your use of the data. \[...\]

This requirement allows users to make an informed decision about whether or not to grant your app access.

## Best practices for purpose strings

A purpose string that only restates the name of the resource, or promises a general benefit without saying what your app actually does, doesn't meet the requirement.

### Explain specifically how your app will use the data.

#### Do

- Name the specific feature or outcome the data makes possible.

- Write a separate purpose string for every protected resource your app requests.

#### Don't

- Don't obscure who has access to data behind a vague benefit or a passive construction, such as, "Your data will be used to provide a better experience."

- Don't restate the name of the resource without explaining its use.

### Provide an example of how the data will be used.

#### Do

- Give a concrete example of what your app does with the data.

- Write one brief, complete sentence in active voice and sentence case, ending with a period.

#### Don't

- Don't fill the request with marketing copy or a full feature list.

| Insufficient examples                                    | Clear and specific examples                                                                                              |
|----------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------|
| "To use location."                                       | "The app uses location data to determine the recommended route to your destination and provide turn-by-turn directions." |
| "Your data will be used to provide a better experience." | "The app uses tracking data to deliver personalized advertising for products that are most relevant to you."             |

## FAQs

### Do purpose strings need to be localized?

Yes. If your app supports localizations for a global audience, you must provide localized purpose strings. Set your app to each localization and test to confirm the correct localized text appears in the permission request. Learn more about [app localization](https://developer.apple.com/localization/#whats-new).

### A third-party SDK in my app requests permissions. Am I responsible for its purpose strings?

Yes. As stated in the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#introduction) and the [Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/#b333), you're responsible for everything in your app, including SDKs, libraries, and other code from third parties. SDKs can reference APIs that access protected resources such as location, sometimes without your realizing it. If your app has a valid reason to access a resource, define a purpose string on the Info.plist that describes your app's specific use case. If it doesn't, remove references to those APIs from your app's binary. Familiarize yourself with the resources an SDK may try to access before you submit.

**Related** [App Review Guideline 5.1.1](https://developer.apple.com/app-store/review/guidelines/#5.1.1) [Requesting access to protected resources](https://developer.apple.com/documentation/UIKit/requesting-access-to-protected-resources) [Human Interface Guidelines: Privacy](https://developer.apple.com/design/human-interface-guidelines/privacy) [Provide information for a complete review](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)
