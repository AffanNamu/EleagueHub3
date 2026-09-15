import Flutter
import UIKit
import Firebase
import GoogleMobileAds
import GoogleSignIn

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // firebase_core / firebase_messaging / firebase_auth / cloud_firestore /
    // firebase_storage / firebase_crashlytics all require this.
    FirebaseApp.configure()

    // google_mobile_ads
    GADMobileAds.sharedInstance().start(completionHandler: nil)

    // Required for firebase_messaging remote-notification delivery.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // google_sign_in: when the Google account picker hands off to the Google
  // app (if installed) or an external browser instead of staying in-app,
  // iOS returns control via this URL callback, not a normal completion
  // handler. Without routing it to GIDSignIn, the plugin's signIn() future
  // never resolves or rejects -- the user picks an account and the app just
  // sits on its loading spinner until Dart's own timeout eventually fires,
  // instead of ever coming back into the app.
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if GIDSignIn.sharedInstance.handle(url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }
}
