<!--
Source: https://developer.apple.com/documentation/declaredagerange
Final URL: https://developer.apple.com/tutorials/data/documentation/declaredagerange.json
Retrieved (UTC): 2026-11-22T04:12:29Z
Raw file: declared-age-range.json
SHA-256 of raw: 4e4f4ce9e531c0914620157dadf40eff8bcc2cd530fb7ae812880207c240e2a8
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# Declared Age Range

_Framework_

Platforms: iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0, macOS 26.0

Create age-appropriate experiences in your app by asking people to share their age range.

### Overview

Use the Declared Age Range API to request that people share their age range with your app. For children in a Family Sharing group, a parent or guardian or the Family Organizer can decide whether to always share a child’s age information with your app, ask the child every time, or never share their age information. Along with an age range, the system returns an [AgeRangeService.AgeRangeDeclaration](https://developer.apple.com/documentation/declaredagerange/agerangeservice/agerangedeclaration) for the age range a person provides. To use the Declared Age Range API, add the [com.apple.developer.declared-age-range](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.declared-age-range) entitlement to your app by enabling the Declared Age Range capability on your target in Xcode. For more information, see [Adding capabilities to your app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app).

> **Important:** Data from the Declared Age Range API is based on information declared by a person, or their parent or guardian, and may be confirmed using a method like a credit card or government ID. You are solely responsible for ensuring compliance with associated laws or regulations that may apply to your app.

## Essentials

- [com.apple.developer.declared-age-range](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.declared-age-range) — A Boolean value indicating whether your app may request a person’s age range.

- [Requesting people’s age range information in your app](https://developer.apple.com/documentation/declaredagerange/requesting-people-share-their-age-range-with-your-app) — Ask people to share their age range with your app, and tailor features for adults, teens, and children while preserving privacy.

- [Implementing age assurance and permissions](https://developer.apple.com/documentation/declaredagerange/implementing-age-assurance-and-permissions) — Create a significant change flow to inform people about important updates in your app and request age-related permissions.

## Age range requests

- [AgeRangeService](https://developer.apple.com/documentation/declaredagerange/agerangeservice) — A request for the age range of a person logged onto the current device.

- [DeclaredAgeRangeAction](https://developer.apple.com/documentation/declaredagerange/declaredagerangeaction) — An action that requests a person’s age range.

## Significant change acknowledgment

- [SignificantUpdateAction](https://developer.apple.com/documentation/declaredagerange/significantupdateaction) — An action that presents a system sheet for significant app update acknowledgments.