<!--
Source: https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes
Final URL: https://developer.apple.com/tutorials/data/documentation/bundleresources/information-property-list/uibackgroundmodes.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: uibackgroundmodes.json
SHA-256 of raw: 393d89a267233ce1a4e7506bf6b11e69775944775d6c3ee1ad7d17d370b57920
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# UIBackgroundModes

_Property List Key_

Platforms: iOS 4.0, iPadOS 4.0, visionOS 1.0, watchOS 4.0

Services provided by an app that require it to run in the background.

### Discussion

To add this key to your Information Property List, enable the Background Modes capability in Xcode. For information on configuring background execution modes and the platforms that support them, see [Configuring background execution modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes).

## Background execution

- [WKBackgroundModes](https://developer.apple.com/documentation/bundleresources/information-property-list/wkbackgroundmodes) — The services a watchOS app provides that require it to continue running in the background.

- [BGTaskSchedulerPermittedIdentifiers](https://developer.apple.com/documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers) — An array of strings containing developer-specified task identifiers in reverse URL notation.

- [LSBackgroundOnly](https://developer.apple.com/documentation/bundleresources/information-property-list/lsbackgroundonly) — A Boolean value indicating whether the app runs only in the background.