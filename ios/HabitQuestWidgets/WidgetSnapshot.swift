import Foundation
import SwiftUI
import WidgetKit

/// Every name shared with the Dart widget bridge. Keep these in sync with
/// `lib/features/widgets_bridge/widget_constants.dart` (contract:
/// `docs/WIDGETS.md`).
enum WidgetConstants {
  static let appGroupId = "group.com.vvs.habitquest"
  static let snapshotKey = "hq_widget_snapshot"

  static let todayHabitsKind = "TodayHabitsWidget"
  static let dailyQuoteKind = "DailyQuoteWidget"

  static let stateOk = "ok"
  static let stateNoHabits = "noHabits"

  static let openURL = URL(string: "habitquest://open")!
  static let quotesURL = URL(string: "habitquest://quotes")!
  static let toggleURIPrefix = "habitquest://widget/toggle?habitId="
}

/// The snapshot JSON the app writes (schema `version` 1). The widgets only
/// ever read it; unknown fields are ignored and every field is optional so a
/// newer app never breaks an older widget.
struct WidgetSnapshot: Decodable {
  struct Habit: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String?
    let color: Int64?
    let colorHex: String?
    let done: Bool
    let toggleUri: String?

    enum CodingKeys: String, CodingKey {
      case id, name, emoji, color, colorHex, done, toggleUri
    }

    init(
      id: String, name: String, emoji: String?, color: Int64?, colorHex: String?,
      done: Bool, toggleUri: String?
    ) {
      self.id = id
      self.name = name
      self.emoji = emoji
      self.color = color
      self.colorHex = colorHex
      self.done = done
      self.toggleUri = toggleUri
    }

    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      id = try c.decode(String.self, forKey: .id)
      name = (try? c.decode(String.self, forKey: .name)) ?? ""
      emoji = try? c.decodeIfPresent(String.self, forKey: .emoji)
      color = try? c.decodeIfPresent(Int64.self, forKey: .color)
      colorHex = try? c.decodeIfPresent(String.self, forKey: .colorHex)
      done = (try? c.decodeIfPresent(Bool.self, forKey: .done)) ?? false
      toggleUri = try? c.decodeIfPresent(String.self, forKey: .toggleUri)
    }

    /// The check-off URI: `toggleUri` as given, or built from the id.
    var toggleURL: URL? {
      if let uri = toggleUri, let url = URL(string: uri) { return url }
      let encoded =
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
      return URL(string: WidgetConstants.toggleURIPrefix + encoded)
    }

    func with(done: Bool) -> Habit {
      Habit(
        id: id, name: name, emoji: emoji, color: color, colorHex: colorHex,
        done: done, toggleUri: toggleUri)
    }

    /// The habit colour (`color` is ARGB `0xAARRGGBB`; `colorHex` is
    /// `#RRGGBB`).
    var tint: Color {
      if let argb = color {
        let value = UInt32(truncatingIfNeeded: argb)
        return Color(
          .sRGB,
          red: Double((value >> 16) & 0xFF) / 255,
          green: Double((value >> 8) & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255,
          opacity: 1)
      }
      if let hex = colorHex?.trimmingCharacters(in: CharacterSet(charactersIn: "#")),
        let value = UInt32(hex, radix: 16)
      {
        return Color(
          .sRGB,
          red: Double((value >> 16) & 0xFF) / 255,
          green: Double((value >> 8) & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255,
          opacity: 1)
      }
      return .accentColor
    }
  }

  struct Quote: Decodable, Hashable {
    let text: String
    let author: String?
    let attribution: String?

    /// Ready-to-display attribution ("— Unknown" for anonymous quotes).
    var displayAttribution: String {
      if let attribution, !attribution.isEmpty { return attribution }
      if let author, !author.isEmpty { return "— \(author)" }
      return "— Unknown"
    }
  }

  let version: Int?
  let date: String?
  let state: String?
  let habits: [Habit]?
  let quote: Quote?
}

/// What a widget shows for one timeline entry: the snapshot interpreted for
/// a given moment (state, and `done` cleared when the snapshot is from an
/// earlier day).
struct WidgetContent: Hashable {
  enum State: Hashable {
    case ok
    case noHabits
    case signedOut
  }

  let state: State
  let habits: [WidgetSnapshot.Habit]
  let quote: WidgetSnapshot.Quote?

  var doneCount: Int { habits.filter(\.done).count }
  var totalCount: Int { habits.count }

  static let signedOut = WidgetContent(state: .signedOut, habits: [], quote: nil)

  /// Sample data for the widget gallery and placeholders.
  static let sample = WidgetContent(
    state: .ok,
    habits: [
      .init(
        id: "1", name: "Morning walk", emoji: "🚶", color: 0xFF4C_C9F0, colorHex: nil,
        done: true, toggleUri: nil),
      .init(
        id: "2", name: "Read 10 pages", emoji: "📚", color: 0xFFF7_2585, colorHex: nil,
        done: false, toggleUri: nil),
      .init(
        id: "3", name: "Drink water", emoji: "💧", color: 0xFF4A_DE80, colorHex: nil,
        done: false, toggleUri: nil),
      .init(
        id: "4", name: "Meditate", emoji: "🧘", color: 0xFFFB_BF24, colorHex: nil,
        done: false, toggleUri: nil),
    ],
    quote: .init(
      text: "The secret of getting ahead is getting started.", author: "Mark Twain",
      attribution: "— Mark Twain"))

  /// Interprets [snapshot] for the local calendar day containing [date].
  static func from(_ snapshot: WidgetSnapshot?, at date: Date) -> WidgetContent {
    guard let snapshot else { return .signedOut }
    let quote = snapshot.quote
    switch snapshot.state {
    case WidgetConstants.stateOk:
      let stale = isBeforeToday(snapshot.date, now: date)
      let habits = (snapshot.habits ?? []).map { stale ? $0.with(done: false) : $0 }
      if habits.isEmpty { return WidgetContent(state: .noHabits, habits: [], quote: quote) }
      return WidgetContent(state: .ok, habits: habits, quote: quote)
    case WidgetConstants.stateNoHabits:
      return WidgetContent(state: .noHabits, habits: [], quote: quote)
    default:
      // `signedOut`, unknown or missing.
      return WidgetContent(state: .signedOut, habits: [], quote: quote)
    }
  }

  /// True when the snapshot's `yyyy-MM-dd` day is before the local day of
  /// [now]. String comparison works because the format is zero-padded.
  static func isBeforeToday(_ day: String?, now: Date) -> Bool {
    guard let day, !day.isEmpty else { return true }
    return day < dayKey(now)
  }

  static func dayKey(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }
}

enum SnapshotStore {
  /// Reads the snapshot the app wrote, or `nil` when there is none yet (the
  /// app has never run) or it cannot be decoded.
  static func load() -> WidgetSnapshot? {
    guard
      let defaults = UserDefaults(suiteName: WidgetConstants.appGroupId),
      let json = defaults.string(forKey: WidgetConstants.snapshotKey),
      let data = json.data(using: .utf8)
    else { return nil }
    return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
  }
}

/// One timeline entry shared by both widgets.
struct SnapshotEntry: TimelineEntry {
  let date: Date
  let content: WidgetContent
}

/// Timeline provider shared by both widgets: one entry now and one at the
/// next local midnight (with the check marks cleared, see
/// `WidgetContent.from`). After the midnight entry WidgetKit asks again. The
/// app also reloads both kinds whenever it rewrites the snapshot.
struct SnapshotProvider: TimelineProvider {
  func placeholder(in context: Context) -> SnapshotEntry {
    SnapshotEntry(date: Date(), content: .sample)
  }

  func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
    let now = Date()
    let snapshot = SnapshotStore.load()
    // The widget gallery shows sample data until the app has written a
    // snapshot.
    if context.isPreview && snapshot == nil {
      completion(SnapshotEntry(date: now, content: .sample))
      return
    }
    completion(SnapshotEntry(date: now, content: .from(snapshot, at: now)))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
    let now = Date()
    let midnight = Calendar.current.nextMidnight(after: now)
    let snapshot = SnapshotStore.load()
    let entries = [
      SnapshotEntry(date: now, content: .from(snapshot, at: now)),
      SnapshotEntry(date: midnight, content: .from(snapshot, at: midnight)),
    ]
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}

extension Calendar {
  /// The next local midnight after [date].
  func nextMidnight(after date: Date) -> Date {
    let start = startOfDay(for: date)
    return self.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
  }
}
