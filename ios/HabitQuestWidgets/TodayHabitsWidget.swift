import SwiftUI
import WidgetKit

/// "Today's habits": today's due habits with emoji, name and a check button.
///
/// iOS 17+: the check button runs `HabitToggleIntent` (home_widget background
/// callback), so the habit is checked off without opening the app.
/// Below iOS 17: the check button is a `Link` to the habit's toggle URI, which
/// opens the app and toggles it there. Small widgets only support one tap
/// target below iOS 17, so there the whole widget opens the app.
struct TodayHabitsWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetConstants.todayHabitsKind, provider: SnapshotProvider()) {
      entry in
      TodayHabitsView(content: entry.content)
    }
    .configurationDisplayName("Today's habits")
    .description("Check off today's habits right from your Home Screen.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}

struct TodayHabitsView: View {
  @Environment(\.widgetFamily) private var family
  let content: WidgetContent

  var body: some View {
    Group {
      switch content.state {
      case .signedOut:
        OpenAppPrompt(title: "Open HabitQuest", message: "Sign in to see today's habits.")
      case .noHabits:
        OpenAppPrompt(title: "No habits today", message: "Open HabitQuest to plan your quest.")
      case .ok:
        habitList
      }
    }
    .widgetURL(WidgetConstants.openURL)
    .widgetBackground(WidgetPalette.background)
  }

  private var maxRows: Int {
    switch family {
    case .systemLarge: return 8
    default: return 3
    }
  }

  private var habitList: some View {
    let shown = Array(content.habits.prefix(maxRows))
    let hidden = content.habits.count - shown.count
    return VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
      header
      ForEach(shown) { habit in
        HabitRow(habit: habit, compact: family == .systemSmall)
      }
      Spacer(minLength: 0)
      if hidden > 0 {
        Text("+\(hidden) more")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var header: some View {
    HStack(spacing: 6) {
      Text(family == .systemSmall ? "Today" : "Today's habits")
        .font(.headline)
        .foregroundStyle(WidgetPalette.brand)
        .lineLimit(1)
      Spacer(minLength: 4)
      Text("\(content.doneCount)/\(content.totalCount)")
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }
}

struct HabitRow: View {
  let habit: WidgetSnapshot.Habit
  let compact: Bool

  var body: some View {
    HStack(spacing: compact ? 6 : 10) {
      Text(emoji)
        .font(compact ? .body : .title3)
        .frame(width: compact ? 26 : 32, height: compact ? 26 : 32)
        .background(habit.tint.opacity(0.22), in: Circle())
      Text(habit.name)
        .font(compact ? .caption : .subheadline)
        .lineLimit(1)
        .strikethrough(habit.done, color: .secondary)
        .foregroundStyle(habit.done ? .secondary : .primary)
      Spacer(minLength: 2)
      CheckButton(habit: habit, allowLink: !compact)
    }
  }

  private var emoji: String {
    if let emoji = habit.emoji, !emoji.isEmpty { return emoji }
    return "⭐️"
  }
}

/// The per-habit check button (see `TodayHabitsWidget` for the iOS 17 split).
struct CheckButton: View {
  let habit: WidgetSnapshot.Habit
  /// Whether a `Link` may be used below iOS 17 (not in small widgets).
  let allowLink: Bool

  var body: some View {
    if #available(iOSApplicationExtension 17.0, *) {
      Button(
        intent: HabitToggleIntent(url: habit.toggleURL, appGroup: WidgetConstants.appGroupId)
      ) {
        CheckMark(done: habit.done, tint: habit.tint)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(accessibilityText)
    } else if allowLink, let url = habit.toggleURL {
      Link(destination: url) {
        CheckMark(done: habit.done, tint: habit.tint)
      }
      .accessibilityLabel(accessibilityText)
    } else {
      CheckMark(done: habit.done, tint: habit.tint)
        .accessibilityLabel(habit.done ? "\(habit.name), done" : "\(habit.name), not done")
    }
  }

  private var accessibilityText: String {
    habit.done ? "Mark \(habit.name) as not done" : "Check off \(habit.name)"
  }
}

struct CheckMark: View {
  let done: Bool
  let tint: Color

  var body: some View {
    Image(systemName: done ? "checkmark.circle.fill" : "circle")
      .font(.title3)
      .foregroundStyle(done ? tint : Color.secondary)
      .frame(width: 30, height: 30)
      .contentShape(Rectangle())
  }
}
