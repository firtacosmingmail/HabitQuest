import SwiftUI
import WidgetKit

/// The HabitQuest widget extension. Both widgets read the snapshot the app's
/// widget bridge writes into the App Group (docs/WIDGETS.md).
@main
struct HabitQuestWidgetsBundle: WidgetBundle {
  var body: some Widget {
    TodayHabitsWidget()
    DailyQuoteWidget()
  }
}
