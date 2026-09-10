import Flutter
import UIKit
import Firebase
import GoogleMobileAds

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
}
