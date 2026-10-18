import Flutter
import UIKit
import UserNotifications
import home_widget

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications: deliver reminders while the app is in the
    // foreground and route taps back to Flutter.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    GeneratedPluginRegistrant.register(with: self)
    // Home-screen widget check-offs (iOS 17+, HabitToggleIntent): the headless
    // engine home_widget starts for the background callback needs the plugins
    // too, or the Dart callback cannot reach the shared storage
    // (docs/WIDGETS.md).
    if #available(iOS 17, *) {
      HomeWidgetBackgroundWorker.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
