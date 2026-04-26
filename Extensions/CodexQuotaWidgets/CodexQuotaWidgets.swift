import CodexQuotaKit
import SwiftUI
import WidgetKit

struct CodexQuotaEntry: TimelineEntry {
  let date: Date
  let snapshot: QuotaSnapshot
}

struct CodexQuotaTimelineProvider: TimelineProvider {
  func placeholder(in context: Context) -> CodexQuotaEntry {
    CodexQuotaEntry(date: Date(), snapshot: .placeholder())
  }

  func getSnapshot(in context: Context, completion: @escaping (CodexQuotaEntry) -> Void) {
    completion(CodexQuotaEntry(date: Date(), snapshot: cachedSnapshot()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CodexQuotaEntry>) -> Void) {
    let now = Date()
    let entry = CodexQuotaEntry(date: now, snapshot: cachedSnapshot())
    completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(5 * 60))))
  }

  private func cachedSnapshot() -> QuotaSnapshot {
    QuotaSnapshotCache().load() ?? .placeholder()
  }
}

struct CodexQuotaWidget: Widget {
  let kind = "com.local.CodexQuotaGlass.widget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: CodexQuotaTimelineProvider()) { entry in
      CodexQuotaWidgetView(entry: entry)
    }
    .configurationDisplayName("Codex Quota")
    .description("Shows five-hour and weekly Codex quota.")
    .supportedFamilies([.systemSmall, .systemMedium])
    .contentMarginsDisabled()
  }
}

struct CodexQuotaWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: CodexQuotaEntry

  var body: some View {
    Group {
      if entry.snapshot.isPlaceholder {
        loggedOut
      } else {
        switch family {
        case .systemMedium:
          medium
        default:
          small
        }
      }
    }
    .containerBackground(for: .widget) {
      WidgetGlassBackground()
    }
    .widgetURL(URL(string: "codexquotaglass-noop://widget"))
  }

  private var loggedOut: some View {
    VStack(alignment: .leading, spacing: 0) {
      widgetHeader(title: family == .systemSmall ? "Codex" : "Codex Quota", showsTimestamp: false)

      Spacer(minLength: 10)

      VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
        Text("去登录")
          .font(.system(size: family == .systemSmall ? 26 : 30, weight: .semibold, design: .rounded))
          .lineLimit(1)
          .minimumScaleFactor(0.72)

        Text("登录后显示剩余额度")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
      }

      Spacer(minLength: 10)

      HStack(spacing: 6) {
        Image(systemName: "safari")
          .font(.caption.weight(.semibold))
        Text("Codex")
          .font(.caption2.weight(.semibold))
      }
      .foregroundStyle(.secondary)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 0) {
      widgetHeader(title: "Codex", showsTimestamp: false)

      Spacer(minLength: 8)

      WidgetPrimaryQuotaBlock(
        window: entry.snapshot.fiveHour,
        resetText: QuotaFormatting.resetClock(entry.snapshot.fiveHour.resetsAt),
        percentSize: 34,
        meterHeight: 8
      )

      Spacer(minLength: 9)

      Divider()
        .opacity(0.45)

      Spacer(minLength: 8)

      WidgetSecondaryQuotaLine(
        window: entry.snapshot.weekly,
        resetText: QuotaFormatting.resetDays(entry.snapshot.weekly.resetsAt, now: entry.date),
        meterHeight: 6
      )
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var medium: some View {
    VStack(alignment: .leading, spacing: 0) {
      widgetHeader(title: "Codex Quota", showsTimestamp: true)

      Spacer(minLength: 10)

      HStack(spacing: 14) {
        WidgetQuotaMeterCard(
          window: entry.snapshot.fiveHour,
          resetText: QuotaFormatting.resetClock(entry.snapshot.fiveHour.resetsAt)
        )

        WidgetQuotaMeterCard(
          window: entry.snapshot.weekly,
          resetText: QuotaFormatting.resetDays(entry.snapshot.weekly.resetsAt, now: entry.date)
        )
      }
      .frame(maxHeight: .infinity)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func widgetHeader(title: String, showsTimestamp: Bool) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "sparkles")
        .symbolRenderingMode(.hierarchical)
        .font(.caption.weight(.semibold))

      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(title)
          .font(.caption.weight(.semibold))
          .lineLimit(1)

        if showsTimestamp {
          Text("更新于 \(QuotaFormatting.capturedTime(entry.snapshot.capturedAt))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
      }

      Spacer(minLength: 0)
    }
  }
}

private struct WidgetPrimaryQuotaBlock: View {
  var window: RateLimitWindow
  var resetText: String
  var percentSize: CGFloat
  var meterHeight: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(window.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Spacer(minLength: 0)

        Text(resetText)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(QuotaFormatting.percent(window.remainingPercent))
          .font(.system(size: percentSize, weight: .semibold, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.68)

        Spacer(minLength: 0)

        Text("剩余")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      WidgetContinuousMeter(value: window.remainingFraction, height: meterHeight)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct WidgetSecondaryQuotaLine: View {
  var window: RateLimitWindow
  var resetText: String
  var meterHeight: CGFloat

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(window.title)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text(QuotaFormatting.percent(window.remainingPercent))
          .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.72)

        Spacer(minLength: 0)

        Text(resetText)
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }

      WidgetContinuousMeter(value: window.remainingFraction, height: meterHeight)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct WidgetQuotaMeterCard: View {
  var window: RateLimitWindow
  var resetText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      titleRow

      Spacer(minLength: 8)

      Text(QuotaFormatting.percent(window.remainingPercent))
        .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.68)

      Spacer(minLength: 8)

      WidgetContinuousMeter(value: window.remainingFraction, height: 8)

      Spacer(minLength: 7)

      HStack {
        Text("剩余")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Text("已用 \(QuotaFormatting.percent(window.usedPercent))")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }

  private var titleRow: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text(window.title)
        .font(.caption.weight(.semibold))
        .lineLimit(1)

      Spacer(minLength: 4)

      Text(resetText)
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
  }
}

private struct WidgetContinuousMeter: View {
  var value: Double
  var height: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let normalizedValue = min(1, max(0, value))
      let fillWidth = max(height, proxy.size.width * normalizedValue)

      ZStack(alignment: .leading) {
        Capsule(style: .continuous)
          .fill(Color.primary.opacity(0.16))

        Capsule(style: .continuous)
          .fill(Color.primary.opacity(0.88))
          .frame(width: fillWidth)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
  }
}

private struct WidgetGlassBackground: View {
  var body: some View {
    ContainerRelativeShape()
      .fill(.regularMaterial)
      .overlay {
        ContainerRelativeShape()
          .stroke(.quaternary, lineWidth: 1)
      }
  }
}

@main
struct CodexQuotaWidgetBundle: WidgetBundle {
  var body: some Widget {
    CodexQuotaWidget()
  }
}
