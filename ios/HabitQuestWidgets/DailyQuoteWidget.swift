import SwiftUI
import WidgetKit

/// "Daily quote": today's quote and author. A tap opens the Quotes screen
/// (`habitquest://quotes`). Home Screen (small, medium) and, on iOS 16+, the
/// Lock Screen (rectangular and inline).
struct DailyQuoteWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: WidgetConstants.dailyQuoteKind, provider: SnapshotProvider()) {
      entry in
      DailyQuoteView(content: entry.content)
    }
    .configurationDisplayName("Daily quote")
    .description("Today's uplifting quote from HabitQuest.")
    .supportedFamilies(Self.families)
  }

  private static var families: [WidgetFamily] {
    if #available(iOSApplicationExtension 16.0, *) {
      return [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
    }
    return [.systemSmall, .systemMedium]
  }
}

struct DailyQuoteView: View {
  @Environment(\.widgetFamily) private var family
  let content: WidgetContent

  var body: some View {
    Group {
      if let quote = content.quote {
        quoteView(quote)
      } else {
        emptyView
      }
    }
    .widgetURL(content.quote == nil ? WidgetConstants.openURL : WidgetConstants.quotesURL)
    .widgetBackground(background)
  }

  @ViewBuilder
  private var background: some View {
    if isAccessory {
      Color.clear
    } else {
      LinearGradient(
        colors: [WidgetPalette.brand.opacity(0.18), WidgetPalette.background],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    }
  }

  private var isAccessory: Bool {
    if #available(iOSApplicationExtension 16.0, *) {
      return family == .accessoryRectangular || family == .accessoryInline
    }
    return false
  }

  @ViewBuilder
  private func quoteView(_ quote: WidgetSnapshot.Quote) -> some View {
    if #available(iOSApplicationExtension 16.0, *), family == .accessoryInline {
      Text(quote.text)
    } else if #available(iOSApplicationExtension 16.0, *), family == .accessoryRectangular {
      VStack(alignment: .leading, spacing: 1) {
        Text(quote.text)
          .font(.caption)
          .lineLimit(3)
          .minimumScaleFactor(0.8)
        Text(quote.displayAttribution)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        Image(systemName: "quote.opening")
          .font(.caption.weight(.bold))
          .foregroundStyle(WidgetPalette.brand)
        Text(quote.text)
          .font(family == .systemSmall ? .footnote.weight(.medium) : .body.weight(.medium))
          .lineLimit(family == .systemSmall ? 5 : 4)
          .minimumScaleFactor(0.75)
        Spacer(minLength: 0)
        Text(quote.displayAttribution)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  @ViewBuilder
  private var emptyView: some View {
    if isAccessory {
      Text("Open HabitQuest")
    } else {
      OpenAppPrompt(
        title: "Open HabitQuest",
        message: content.state == .signedOut
          ? "Sign in to get a quote every day." : "Today's quote will appear here.")
    }
  }
}
