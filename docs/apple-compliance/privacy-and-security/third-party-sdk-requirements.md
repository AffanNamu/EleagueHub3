<!--
Source: https://developer.apple.com/support/third-party-SDK-requirements/
Final URL: https://developer.apple.com/support/third-party-SDK-requirements/
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: third-party-sdk-requirements.html
SHA-256 of raw: a45f09ffa6dd7d7e71485035848acb7fcbf4bd4fcfc0a32f865a53ada30a12f0
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# Third-party SDK requirements

Third-party software development kits (SDKs) can provide great functionality for apps; they can also have the potential to impact user privacy in ways that aren’t obvious to developers and users. As a reminder, when you use a third-party SDK with your app, you are responsible for all the code the SDK includes in your app, and need to be aware of its data collection and use practices. At [WWDC23](/videos/play/wwdc2023/10060/), we introduced new privacy manifests and signatures for SDKs to help bring more awareness for how third-party SDKs use data. This functionality is a step forward for all apps, and we encourage all SDKs to adopt it to better support the apps that depend on them.

#### Privacy Manifests

[Privacy manifest files](/documentation/bundleresources/privacy_manifest_files/describing_data_use_in_privacy_manifests) outline the privacy practices of the third-party code in an app, in a single standard format. When you prepare to distribute your app, Xcode will combine the privacy manifests across all the third-party SDKs used by your app into a single, easy-to-use report. With one comprehensive report that summarizes all the third-party SDKs found in an app, it will be even easier for you to create more accurate Privacy Nutrition Labels.

#### Signatures for SDKs

When you adopt a new version of a third-party SDK in your app, Xcode will validate that it was signed by the same developer, improving the integrity of your software supply chain.

#### SDKs that require a privacy manifest and signature

The following are commonly used SDKs in apps on the App Store. You must include the privacy manifest for any SDK listed below when you submit new apps in App Store Connect that include those SDKs, or when you submit an app update that adds one of the listed SDKs as part of the update. Signatures are also required in these cases where the listed SDKs are used as binary dependencies. Any version of a listed SDK, as well as any SDKs that repackage those on the list, are included in the requirement.

- Abseil
- AFNetworking
- Alamofire
- AppAuth
- BoringSSL / openssl_grpc
- Capacitor
- Charts
- connectivity_plus
- Cordova
- device_info_plus
- DKImagePickerController
- DKPhotoGallery
- FBAEMKit
- FBLPromises
- FBSDKCoreKit
- FBSDKCoreKit_Basics
- FBSDKLoginKit
- FBSDKShareKit
- file_picker
- FirebaseABTesting
- FirebaseAuth
- FirebaseCore
- FirebaseCoreDiagnostics
- FirebaseCoreExtension
- FirebaseCoreInternal
- FirebaseCrashlytics
- FirebaseDynamicLinks
- FirebaseFirestore
- FirebaseInstallations
- FirebaseMessaging
- FirebaseRemoteConfig
- Flutter
- flutter_inappwebview
- flutter_local_notifications
- fluttertoast
- FMDB
- geolocator_apple
- GoogleDataTransport
- GoogleSignIn
- GoogleToolboxForMac
- GoogleUtilities
- grpcpp
- GTMAppAuth
- GTMSessionFetcher
- hermes
- image_picker_ios
- IQKeyboardManager
- IQKeyboardManagerSwift
- Kingfisher
- leveldb
- Lottie
- MBProgressHUD
- nanopb
- OneSignal
- OneSignalCore
- OneSignalExtension
- OneSignalOutcomes
- OpenSSL
- OrderedSet
- package_info
- package_info_plus
- path_provider
- path_provider_ios
- Promises
- Protobuf
- Reachability
- RealmSwift
- RxCocoa
- RxRelay
- RxSwift
- SDWebImage
- share_plus
- shared_preferences_ios
- SnapKit
- sqflite
- Starscream
- SVProgressHUD
- SwiftyGif
- SwiftyJSON
- Toast
- UnityFramework
- url_launcher
- url_launcher_ios
- video_player_avfoundation
- wakelock
- webview_flutter_wkwebview
