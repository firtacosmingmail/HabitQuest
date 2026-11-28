import AppIntents
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

/// Lets the system wake the (suspended or terminated) app in the background to
/// run HabitToggleIntent, as home_widget documents. Declared here, not in
/// HabitToggleIntent.swift: that file is also compiled into the widget
/// extension, where ForegroundContinuableIntent is unavailable; there, Xcode
/// 27 failed the release archive ("'HabitToggleIntent' is only available in
/// iOS 17 or newer") despite `@available(iOSApplicationExtension, unavailable)`.
@available(iOS 17, *)
extension HabitToggleIntent: ForegroundContinuableIntent {}
