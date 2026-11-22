<!--
Source: https://developer.apple.com/documentation/callkit
Final URL: https://developer.apple.com/tutorials/data/documentation/callkit.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: callkit.json
SHA-256 of raw: 258834f1d0b4d97a09e64d9b9c89746f1dd79a41e869fa4aa9d800a29b737d3d
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# CallKit

_Framework_

Platforms: iOS 10.0, iPadOS 10.0, Mac Catalyst 13.0, macOS 13.0, visionOS 1.0, watchOS 9.0

Display the system-calling UI for your app’s VoIP services, and coordinate your calling services with other apps and the system.

### Overview

Use CallKit to integrate your calling services with other call-related apps in the system. CallKit provides the calling interface, and you handle the back-end communication with your VoIP service. See [Making and receiving VoIP calls](https://developer.apple.com/documentation/callkit/making-and-receiving-voip-calls) for more information.

For incoming and outgoing calls, CallKit displays the same interfaces as the Phone app, giving your app a more native look and feel. CallKit also responds appropriately to system-level behaviors, such as Do Not Disturb.

In addition to handling calls, you can use a Call Directory app extension to provide caller ID information and a list of blocked numbers associated with your service. See [Identifying and blocking calls](https://developer.apple.com/documentation/callkit/identifying-and-blocking-calls) for more information.

#### Manage user privacy

With a person’s permission, an installed health research app that uses [SensorKit](https://developer.apple.com/documentation/sensorkit) entitlements may collect Speech Metrics data while your CallKit app is in use. To prevent this, you can set the [SRResearchDataGeneration](https://developer.apple.com/documentation/bundleresources/information-property-list/srresearchdatageneration) information property list key to `NO`.

> **Important:** When a person makes a call in your app that uses CallKit, your app provides the contact information of the recipient to the system. The system may use that information to indicate communication with that person as a suggestion in the Journal app, or in other apps that use the [Journaling Suggestions](https://developer.apple.com/documentation/journalingsuggestions) framework.

#### Become the default calling app

In iOS and iPadOS 18.2 and later, a person may select an app — other than the Phone app or FaceTime — to place calls by default. To make your CallKit or [LiveCommunicationKit](https://developer.apple.com/documentation/livecommunicationkit) app support the default calling app setting, see [Preparing your app to be the default calling app](https://developer.apple.com/documentation/callkit/preparing-your-app-to-be-the-default-calling-app).

## Essentials

- [CXProvider](https://developer.apple.com/documentation/callkit/cxprovider) — An object that represents a telephony provider.

- [CXProviderDelegate](https://developer.apple.com/documentation/callkit/cxproviderdelegate) — A collection of methods that a telephony provider object calls.

- [CXProviderConfiguration](https://developer.apple.com/documentation/callkit/cxproviderconfiguration) — An encapsulation of the configuration of a provider object.

- [Making and receiving VoIP calls](https://developer.apple.com/documentation/callkit/making-and-receiving-voip-calls) — Initiate outgoing calls with VoIP and configure your app to receive incoming calls.

- [VoIP calling with CallKit](https://developer.apple.com/documentation/callkit/voip-calling-with-callkit) — Use the CallKit framework to integrate native VoIP calling.

- [Preparing your app to be the default calling app](https://developer.apple.com/documentation/callkit/preparing-your-app-to-be-the-default-calling-app) — Configure your CallKit or LiveCommunicationKit app so people can set it as the default calling app on their device.

- [CallKit updates](https://developer.apple.com/documentation/updates/callkit) — Learn about important changes to CallKit.

## Incoming calls

- [Responding to VoIP Notifications from PushKit](https://developer.apple.com/documentation/pushkit/responding-to-voip-notifications-from-pushkit) — Receive incoming Voice-over-IP (VoIP) push notifications and use them to display the system call interface to the user.

- [CXCallUpdate](https://developer.apple.com/documentation/callkit/cxcallupdate) — An encapsulation of new and changed information about a call.

- [CXAnswerCallAction](https://developer.apple.com/documentation/callkit/cxanswercallaction) — An encapsulation of the act of answering an incoming call.

## Outgoing calls

- [Sending End-to-End Encrypted VoIP Calls](https://developer.apple.com/documentation/callkit/sending-end-to-end-encrypted-voip-calls) — Initiate VoIP calls when your server can’t determine whether an outgoing notification is a request for a VoIP call due to metadata encryption.

- [CXCallController](https://developer.apple.com/documentation/callkit/cxcallcontroller) — A programmatic interface for interacting with and observing calls.

- [CXTransaction](https://developer.apple.com/documentation/callkit/cxtransaction) — An object that contains zero or more action objects for a call controller to perform.

- [CXStartCallAction](https://developer.apple.com/documentation/callkit/cxstartcallaction) — An encapsulation of the act of initiating an outgoing call.

## Call-related actions

- [CXAction](https://developer.apple.com/documentation/callkit/cxaction) — An abstract class that declares a programmatic interface for objects that represent a telephony action.

- [CXCallAction](https://developer.apple.com/documentation/callkit/cxcallaction) — A programmatic interface for objects that represent a telephony action associated with a call object.

- [CXEndCallAction](https://developer.apple.com/documentation/callkit/cxendcallaction) — An encapsulation of the act of ending a call.

- [CXPlayDTMFCallAction](https://developer.apple.com/documentation/callkit/cxplaydtmfcallaction) — An encapsulation of the act of playing a dual tone multifrequency (DTMF) sequence.

- [CXSetGroupCallAction](https://developer.apple.com/documentation/callkit/cxsetgroupcallaction) — An encapsulation of the act of grouping or ungrouping calls.

- [CXSetHeldCallAction](https://developer.apple.com/documentation/callkit/cxsetheldcallaction) — An encapsulation of the act of placing a call on hold or removing a call from hold.

- [CXSetMutedCallAction](https://developer.apple.com/documentation/callkit/cxsetmutedcallaction) — An encapsulation of the act of muting or unmuting a call.

- [CXSetTranslatingCallAction](https://developer.apple.com/documentation/callkit/cxsettranslatingcallaction) — An encapsulation of the act of translating a call.

## Call information

- [CXCall](https://developer.apple.com/documentation/callkit/cxcall) — A telephony call.

- [CXCallObserver](https://developer.apple.com/documentation/callkit/cxcallobserver) — A programmatic interface for an object that manages a list of active calls and observes call changes.

- [CXCallObserverDelegate](https://developer.apple.com/documentation/callkit/cxcallobserverdelegate) — A collection of methods the system calls when a call changes state.

- [CXHandle](https://developer.apple.com/documentation/callkit/cxhandle) — A way to reach a call recipient, such as a phone number or email address.

## Caller ID

- [Identifying and blocking calls](https://developer.apple.com/documentation/callkit/identifying-and-blocking-calls) — Create a Call Directory app extension to identify and block incoming callers by their phone number.

- [CXCallDirectoryProvider](https://developer.apple.com/documentation/callkit/cxcalldirectoryprovider) — The principal object for a Call Directory app extension for a host app.

- [CXCallDirectoryExtensionContext](https://developer.apple.com/documentation/callkit/cxcalldirectoryextensioncontext) — A programmatic interface for adding identification and blocking entries to a Call Directory app extension.

- [CXCallDirectoryExtensionContextDelegate](https://developer.apple.com/documentation/callkit/cxcalldirectoryextensioncontextdelegate) — A collection of methods a Call Directory extension context object calls when a request fails.

- [CXCallDirectoryManager](https://developer.apple.com/documentation/callkit/cxcalldirectorymanager) — The programmatic interface to an object that manages a Call Directory app extension.

## Reference

- [CallKit Enumerations](https://developer.apple.com/documentation/callkit/callkit-enumerations) — 

- [CallKit Constants](https://developer.apple.com/documentation/callkit/callkit-constants) — 