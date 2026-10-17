import SwiftUI
import WidgetKit

/// Colours that follow the system light/dark appearance.
enum WidgetPalette {
  static let background = Color(uiColor: .systemBackground)
  static let card = Color(uiColor: .secondarySystemBackground)
  static let brand = Color(red: 0.42, green: 0.36, blue: 0.91)  // HabitQuest violet
}

extension View {
  /// The widget background: `containerBackground` on iOS 17+ (required there,
  /// and it gives the system margins), a padded background below.
  @ViewBuilder
  func widgetBackground<Background: View>(_ background: Background) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
      containerBackground(for: .widget) { background }
    } else {
      padding().background(background)
    }
  }
}

/// The "Open HabitQuest" prompt for the `signedOut` and `noHabits` states.
struct OpenAppPrompt: View {
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 6) {
      Image(systemName: "checkmark.seal.fill")
        .font(.title2)
        .foregroundStyle(WidgetPalette.brand)
      Text(title)
        .font(.headline)
        .multilineTextAlignment(.center)
      Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
