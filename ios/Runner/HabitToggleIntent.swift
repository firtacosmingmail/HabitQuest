// Interactive check-off for the "Today's habits" widget (iOS 17+).
//
// This file is a member of BOTH the Runner and the HabitQuestWidgets targets
// (home_widget requirement, docs/WIDGETS.md): the widget builds the button
// with it, and the system runs `perform()` through home_widget's headless
// Flutter engine, which calls the Dart `widgetInteractivityCallback` with the
// habit's toggle URI. Dart then queues the check-off, flips `done` in the
// snapshot and reloads the widgets, all without opening the app.

import AppIntents
import Foundation
import home_widget

@available(iOS 17, *)
public struct HabitToggleIntent: AppIntent {
  public static var title: LocalizedStringResource = "Check off habit"
  public static var description = IntentDescription(
    "Marks a HabitQuest habit as done (or not done) for today.")
  // Only used from the widget; keep it out of Shortcuts and Spotlight.
  public static var isDiscoverable: Bool = false

  @Parameter(title: "Widget URI")
  var url: URL?

  @Parameter(title: "App Group")
  var appGroup: String?

  public init() {}

  public init(url: URL?, appGroup: String?) {
    self.url = url
    self.appGroup = appGroup
  }

  public func perform() async throws -> some IntentResult {
    await HomeWidgetBackgroundWorker.run(
      url: url, appGroup: appGroup ?? "group.com.vvs.habitquest")
    return .result()
  }
}

/// Lets the system wake the (suspended or terminated) app in the background to
/// run the intent, as home_widget documents. Not available in the extension.
@available(iOS 17, *)
@available(iOSApplicationExtension, unavailable)
extension HabitToggleIntent: ForegroundContinuableIntent {}
