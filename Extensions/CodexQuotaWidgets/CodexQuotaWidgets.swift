import AppIntents
import CodexQuotaKit
import SwiftUI
import WidgetKit

struct CodexQuotaEntry: TimelineEntry {
  let date: Date
  let snapshot: QuotaSnapshot
  let localUsageSummary: CodexLocalUsageSummary
  let configuration: CodexTokenUsageConfigurationIntent
}

struct CodexQuotaTimelineProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> CodexQuotaEntry {
    CodexQuotaEntry(
      date: Date(),
      snapshot: .placeholder(),
      localUsageSummary: .widgetPreview(),
      configuration: CodexTokenUsageConfigurationIntent()
    )
  }

  func snapshot(
    for configuration: CodexTokenUsageConfigurationIntent,
    in context: Context
  ) async -> CodexQuotaEntry {
    let summary = cachedSummary()
    return CodexQuotaEntry(
      date: Date(),
      snapshot: cachedSnapshot(),
      localUsageSummary: context.isPreview && summary.parsedEventCount == 0 ? .widgetPreview() : summary,
      configuration: configuration
    )
  }

  func timeline(
    for configuration: CodexTokenUsageConfigurationIntent,
    in context: Context
  ) async -> Timeline<CodexQuotaEntry> {
    let now = Date()
    let entry = CodexQuotaEntry(
      date: now,
      snapshot: cachedSnapshot(),
      localUsageSummary: cachedSummary(),
      configuration: configuration
    )
    return Timeline(entries: [entry], policy: .after(now.addingTimeInterval(5 * 60)))
  }

  private func cachedSnapshot() -> QuotaSnapshot {
    QuotaSnapshotCache().load() ?? .placeholder()
  }

  private func cachedSummary() -> CodexLocalUsageSummary {
    CodexLocalUsageSummaryCache().load() ?? .empty()
  }
}

struct CodexQuotaWidget: Widget {
  let kind = "com.local.CodexQuotaGlass.widget"

  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: kind,
      intent: CodexTokenUsageConfigurationIntent.self,
      provider: CodexQuotaTimelineProvider()
    ) { entry in
      CodexQuotaWidgetView(entry: entry)
    }
    .configurationDisplayName("Codex")
    .description("Shows Codex quota or local token usage.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    .contentMarginsDisabled()
  }
}

struct CodexQuotaWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: CodexQuotaEntry

  var body: some View {
    Group {
      if entry.configuration.contentMode == .tokenUsage {
        CodexTokenUsageWidgetView(
          entry: CodexTokenUsageEntry(
            date: entry.date,
            summary: entry.localUsageSummary,
            configuration: entry.configuration
          )
        )
      } else if entry.snapshot.isPlaceholder {
        loggedOut
      } else if isWeeklyOnly {
        switch family {
        case .systemLarge:
          weeklyOnlyLarge
        case .systemMedium:
          weeklyOnlyMedium
        default:
          weeklyOnlySmall
        }
      } else {
        switch family {
        case .systemLarge:
          large
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

  private var weeklyOnlySmall: some View {
    let weekly = entry.snapshot.weekly

    return VStack(alignment: .leading, spacing: 0) {
      widgetHeader(title: "Codex", showsTimestamp: false, subscriptionText: subscriptionText)

      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text("周额度")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.secondary)

        Text("重置 \(resetText(for: weekly))")
          .font(.system(size: 9, weight: .medium, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text("取消 5h")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(.tertiary)

        Spacer(minLength: 0)
      }
      .lineLimit(1)
      .minimumScaleFactor(0.68)

      Spacer(minLength: 0)

      Text(QuotaFormatting.percent(weekly.remainingPercent))
        .font(.system(size: 66, weight: .semibold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.48)
        .layoutPriority(1)
        .frame(maxWidth: .infinity, alignment: .leading)

      Spacer(minLength: 0)

      WidgetContinuousMeter(value: weekly.remainingFraction, height: 8)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var weeklyOnlyMedium: some View {
    let weekly = entry.snapshot.weekly

    return VStack(alignment: .leading, spacing: 0) {
      widgetHeader(title: "Codex Quota", showsTimestamp: true, subscriptionText: subscriptionText)

      HStack(alignment: .center, spacing: 12) {
        Text(QuotaFormatting.percent(weekly.remainingPercent))
          .font(.system(size: 84, weight: .semibold, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.52)
          .layoutPriority(1)

        Spacer(minLength: 8)

        VStack(alignment: .trailing, spacing: 4) {
          Text("一周剩余")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Text("重置 \(resetText(for: weekly))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)

          Text("已用 \(QuotaFormatting.percent(weekly.usedPercent))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Text("新版取消 5h")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

      WidgetContinuousMeter(value: weekly.remainingFraction, height: 10)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var weeklyOnlyLarge: some View {
    let weekly = entry.snapshot.weekly

    return VStack(alignment: .leading, spacing: 0) {
      widgetHeader(title: "Codex Quota", showsTimestamp: true, subscriptionText: subscriptionText)

      Spacer(minLength: 10)

      HStack(alignment: .lastTextBaseline, spacing: 12) {
        Text(QuotaFormatting.percent(weekly.remainingPercent))
          .font(.system(size: 60, weight: .semibold, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.62)

        VStack(alignment: .leading, spacing: 4) {
          Text("一周剩余额度")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Text("已用 \(QuotaFormatting.percent(weekly.usedPercent))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }

        Spacer(minLength: 0)
      }

      Spacer(minLength: 10)

      WidgetContinuousMeter(value: weekly.remainingFraction, height: 10)

      Spacer(minLength: 12)

      VStack(alignment: .leading, spacing: 9) {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
          WidgetQuotaTinyStat(title: "周重置", value: resetText(for: weekly))

          WidgetQuotaTinyStat(title: "已用", value: QuotaFormatting.percent(weekly.usedPercent))

          Spacer(minLength: 0)
        }

        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: "info.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          Label("新版 Codex App 已取消 5h 额度", systemImage: "info.circle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .labelStyle(.titleOnly)

          Spacer(minLength: 0)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var small: some View {
    let primary = entry.snapshot.primaryDisplayWindow
    let secondary = entry.snapshot.secondaryDisplayWindow

    return VStack(alignment: .leading, spacing: 0) {
      widgetHeader(title: "Codex", showsTimestamp: false, subscriptionText: subscriptionText)

      Spacer(minLength: 8)

      WidgetPrimaryQuotaBlock(
        window: primary,
        resetText: resetText(for: primary),
        percentSize: 34,
        meterHeight: 8
      )

      if let secondary {
        Spacer(minLength: 9)

        Divider()
          .opacity(0.45)

        Spacer(minLength: 8)

        WidgetSecondaryQuotaLine(
          window: secondary,
          resetText: resetText(for: secondary),
          meterHeight: 6
        )
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var medium: some View {
    let windows = availableWindows

    return VStack(alignment: .leading, spacing: 0) {
      widgetHeader(title: "Codex Quota", showsTimestamp: true, subscriptionText: subscriptionText)

      Spacer(minLength: 10)

      HStack(spacing: 14) {
        ForEach(windows) { window in
          WidgetQuotaMeterCard(
            window: window,
            resetText: resetText(for: window)
          )
        }
      }
      .frame(maxHeight: .infinity)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var large: some View {
    let primary = entry.snapshot.primaryDisplayWindow
    let secondary = entry.snapshot.secondaryDisplayWindow

    return VStack(alignment: .leading, spacing: 0) {
      widgetHeader(title: "Codex Quota", showsTimestamp: true, subscriptionText: subscriptionText)

      Spacer(minLength: 12)

      WidgetLargeQuotaHero(
        window: primary,
        resetText: resetText(for: primary)
      )

      if let secondary {
        Spacer(minLength: 14)

        Divider()
          .opacity(0.38)

        Spacer(minLength: 14)

        WidgetWeeklyQuotaBand(
          window: secondary,
          resetText: resetText(for: secondary)
        )
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func widgetHeader(
    title: String,
    showsTimestamp: Bool,
    subscriptionText: String? = nil
  ) -> some View {
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

      if let subscriptionText {
        Text(subscriptionText)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
    }
  }

  private var subscriptionText: String {
    entry.snapshot.subscriptionDisplayName
  }

  private var availableWindows: [RateLimitWindow] {
    let windows = entry.snapshot.availableWindows
    return windows.isEmpty ? [entry.snapshot.primaryDisplayWindow] : windows
  }

  private var isWeeklyOnly: Bool {
    !entry.snapshot.fiveHour.isAvailable && entry.snapshot.weekly.isAvailable
  }

  private func resetText(for window: RateLimitWindow) -> String {
    switch window.kind {
    case .fiveHour:
      QuotaFormatting.resetClock(window.resetsAt)
    case .weekly:
      QuotaFormatting.resetDays(window.resetsAt, now: entry.date)
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

private struct WidgetLargeQuotaHero: View {
  var window: RateLimitWindow
  var resetText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(window.title)
          .font(.title3.weight(.semibold))
          .lineLimit(1)

        Text("重置 \(resetText)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Spacer(minLength: 0)
      }

      HStack(alignment: .lastTextBaseline, spacing: 10) {
        Text(QuotaFormatting.percent(window.remainingPercent))
          .font(.system(size: 62, weight: .semibold, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.62)

        VStack(alignment: .leading, spacing: 3) {
          Text("剩余额度")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)

          Text("已用 \(QuotaFormatting.percent(window.usedPercent))")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }

        Spacer(minLength: 0)
      }

      WidgetContinuousMeter(value: window.remainingFraction, height: 10)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct WidgetLargeQuotaFooter: View {
  var fiveHour: RateLimitWindow
  var weekly: RateLimitWindow
  var weeklyResetText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      WidgetWeeklyQuotaBand(window: weekly, resetText: weeklyResetText)

      HStack(spacing: 16) {
        WidgetQuotaTinyStat(title: "5h 已用", value: QuotaFormatting.percent(fiveHour.usedPercent))

        Divider()
          .opacity(0.35)

        WidgetQuotaTinyStat(title: "周剩余", value: QuotaFormatting.percent(weekly.remainingPercent))

        Divider()
          .opacity(0.35)

        WidgetQuotaTinyStat(title: "周重置", value: weeklyResetText)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct WidgetWeeklyQuotaBand: View {
  var window: RateLimitWindow
  var resetText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(window.title)
          .font(.callout.weight(.semibold))
          .lineLimit(1)

        Text(QuotaFormatting.percent(window.remainingPercent))
          .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.7)

        Spacer(minLength: 0)

        Text(resetText)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }

      WidgetContinuousMeter(value: window.remainingFraction, height: 7)
    }
  }
}

private struct WidgetQuotaTinyStat: View {
  var title: String
  var value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)

      Text(value)
        .font(.callout.weight(.semibold).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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

enum TokenUsagePeriodOption: String, AppEnum {
  case none
  case today
  case yesterday
  case last7Days
  case last30Days
  case allTime

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "时间段"

  static let caseDisplayRepresentations: [TokenUsagePeriodOption: DisplayRepresentation] = [
    .none: "不显示",
    .today: "今日",
    .yesterday: "昨日",
    .last7Days: "过去7天",
    .last30Days: "过去30天",
    .allTime: "有史以来",
  ]

  var usagePeriod: CodexUsagePeriod? {
    switch self {
    case .none:
      nil
    case .today:
      .today
    case .yesterday:
      .yesterday
    case .last7Days:
      .last7Days
    case .last30Days:
      .last30Days
    case .allTime:
      .allTime
    }
  }
}

enum WidgetContentModeOption: String, AppEnum {
  case quota
  case tokenUsage

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "内容"

  static let caseDisplayRepresentations: [WidgetContentModeOption: DisplayRepresentation] = [
    .quota: "剩余额度",
    .tokenUsage: "Token 用量",
  ]
}

struct CodexTokenUsageConfigurationIntent: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "Codex"
  static let description = IntentDescription("选择小组件展示剩余额度或本地 token 用量。")

  static var parameterSummary: some ParameterSummary {
    When(\.$contentMode, .equalTo, WidgetContentModeOption.tokenUsage) {
      Switch(.widgetFamily) {
        Case(.systemSmall) {
          Summary("显示 \(\.$contentMode)，时间段 \(\.$firstPeriod)、\(\.$secondPeriod)")
        }
        Case(.systemMedium) {
          Summary("显示 \(\.$contentMode)，时间段 \(\.$firstPeriod)、\(\.$secondPeriod)、\(\.$thirdPeriod)")
        }
        DefaultCase {
          Summary("显示 \(\.$contentMode)，时间段 \(\.$firstPeriod)、\(\.$secondPeriod)、\(\.$thirdPeriod)、\(\.$fourthPeriod)、\(\.$fifthPeriod)")
        }
      }
    } otherwise: {
      Summary("显示 \(\.$contentMode)")
    }
  }

  @Parameter(title: "内容", default: .quota)
  var contentMode: WidgetContentModeOption

  @Parameter(title: "时间段 1", default: .today)
  var firstPeriod: TokenUsagePeriodOption

  @Parameter(title: "时间段 2", default: .yesterday)
  var secondPeriod: TokenUsagePeriodOption

  @Parameter(title: "时间段 3", default: .last7Days)
  var thirdPeriod: TokenUsagePeriodOption

  @Parameter(title: "时间段 4", default: .last30Days)
  var fourthPeriod: TokenUsagePeriodOption

  @Parameter(title: "时间段 5", default: .allTime)
  var fifthPeriod: TokenUsagePeriodOption

  init() {
    contentMode = .quota
    firstPeriod = .today
    secondPeriod = .yesterday
    thirdPeriod = .last7Days
    fourthPeriod = .last30Days
    fifthPeriod = .allTime
  }

  func selectedPeriods(for family: WidgetFamily) -> [CodexUsagePeriod] {
    switch family {
    case .systemSmall:
      return [firstPeriod.usagePeriod, secondPeriod.usagePeriod].compactMap { $0 }.uniqued()
    case .systemMedium:
      return [
        firstPeriod.usagePeriod,
        secondPeriod.usagePeriod,
        thirdPeriod.usagePeriod,
      ].compactMap { $0 }.uniqued()
    default:
      return [
        firstPeriod.usagePeriod,
        secondPeriod.usagePeriod,
        thirdPeriod.usagePeriod,
        fourthPeriod.usagePeriod,
        fifthPeriod.usagePeriod,
      ].compactMap { $0 }.uniqued()
    }
  }
}

struct CodexTokenUsageEntry: TimelineEntry {
  let date: Date
  let summary: CodexLocalUsageSummary
  let configuration: CodexTokenUsageConfigurationIntent
}

struct CodexTokenUsageWidgetView: View {
  @Environment(\.widgetFamily) private var family
  var entry: CodexTokenUsageEntry

  private var selectedSummaries: [CodexUsagePeriodSummary] {
    entry.configuration
      .selectedPeriods(for: family)
      .map { entry.summary.summary(for: $0) }
  }

  var body: some View {
    Group {
      if entry.summary.parsedEventCount == 0 {
        emptyState
      } else if selectedSummaries.isEmpty {
        noSelectionState
      } else {
        switch family {
        case .systemSmall:
          small
        case .systemMedium:
          medium
        default:
          large
        }
      }
    }
    .containerBackground(for: .widget) {
      WidgetGlassBackground()
    }
    .widgetURL(URL(string: "codexquotaglass-noop://token-widget"))
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 0) {
      TokenWidgetHeader(title: family == .systemSmall ? "Token" : "Codex Token", date: nil)

      Spacer(minLength: 10)

      Text("暂无数据")
        .font(.system(size: family == .systemSmall ? 24 : 30, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.75)

      Text("打开 app 后刷新本地日志")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .minimumScaleFactor(0.8)

      Spacer(minLength: 10)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var noSelectionState: some View {
    VStack(alignment: .leading, spacing: 0) {
      TokenWidgetHeader(title: family == .systemSmall ? "Token" : "Codex Token", date: nil)

      Spacer(minLength: 10)

      Text("未选择")
        .font(.system(size: family == .systemSmall ? 24 : 30, weight: .semibold, design: .rounded))
        .lineLimit(1)
        .minimumScaleFactor(0.75)

      Text("编辑小组件后选择时间段")
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .minimumScaleFactor(0.8)

      Spacer(minLength: 10)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var small: some View {
    VStack(alignment: .leading, spacing: 0) {
      if selectedSummaries.count == 1, let summary = selectedSummaries.first {
        TokenWidgetHeader(title: "Token", date: nil, trailingText: "\(summary.period.title) · \(summary.requestCount)次")
      } else {
        TokenWidgetHeader(title: "Token", date: nil)
      }

      Spacer(minLength: selectedSummaries.count == 1 ? 3 : 8)

      if selectedSummaries.count == 1, let summary = selectedSummaries.first {
        WidgetTokenHeroBlock(summary: summary)
      } else {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(selectedSummaries) { summary in
            WidgetTokenPeriodBlock(summary: summary, layout: .compact)
          }
        }
      }

      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var medium: some View {
    VStack(alignment: .leading, spacing: 0) {
      TokenWidgetHeader(title: "Codex Token", date: entry.summary.generatedAt)

      Spacer(minLength: 8)

      if selectedSummaries.count == 1, let summary = selectedSummaries.first {
        WidgetTokenMediumHeroBlock(summary: summary)
      } else {
        VStack(spacing: selectedSummaries.count >= 3 ? 7 : 10) {
          ForEach(selectedSummaries) { summary in
            WidgetTokenPeriodRow(summary: summary)
          }
        }
      }

      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var large: some View {
    VStack(alignment: .leading, spacing: 0) {
      TokenWidgetHeader(title: "Codex Token", date: entry.summary.generatedAt)

      Spacer(minLength: 10)

      WidgetTokenLargeBoard(summaries: selectedSummaries)

      Spacer(minLength: 0)
    }
    .padding(12)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct TokenWidgetHeader: View {
  var title: String
  var date: Date?
  var trailingText: String? = nil

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "chart.bar.xaxis")
        .symbolRenderingMode(.hierarchical)
        .font(.caption.weight(.semibold))

      Text(title)
        .font(.caption.weight(.semibold))
        .lineLimit(1)

      if let date {
        Text("更新于 \(QuotaFormatting.capturedTime(date))")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }

      Spacer(minLength: 0)

      if let trailingText {
        Text(trailingText)
          .font(.caption2.weight(.semibold).monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.68)
      }
    }
  }
}

private enum WidgetTokenPeriodLayout {
  case compact
  case medium
  case tile
}

private struct WidgetTokenMediumHeroBlock: View {
  var summary: CodexUsagePeriodSummary

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(summary.period.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text(QuotaFormatting.tokenCount(summary.metrics.totalTokens))
            .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.56)

          Text("tokens")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 0)

      VStack(alignment: .trailing, spacing: 5) {
        Text("\(summary.requestCount)次")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text(QuotaFormatting.tokenBreakdown(summary.metrics))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(3)
          .multilineTextAlignment(.trailing)
          .minimumScaleFactor(0.7)
      }
      .frame(maxWidth: 150, alignment: .trailing)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
  }
}

private struct WidgetTokenHeroBlock: View {
  var summary: CodexUsagePeriodSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Spacer(minLength: 0)

      Text(QuotaFormatting.tokenCount(summary.metrics.totalTokens))
        .font(.system(size: 92, weight: .semibold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)

      Spacer(minLength: 0)

      WidgetTokenMiniBreakdown(metrics: summary.metrics)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}

private struct WidgetTokenMiniBreakdown: View {
  var metrics: CodexTokenMetrics

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        item("In", value: metrics.inputTokens)
        item("Out", value: metrics.outputTokens)
      }

      HStack(spacing: 6) {
        item("R", value: metrics.reasoningOutputTokens)
        item("Cache", value: metrics.cachedInputTokens)
      }
    }
    .font(.caption2.monospacedDigit())
    .foregroundStyle(.secondary)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func item(_ title: String, value: Int) -> some View {
    HStack(spacing: 2) {
      Text(title)
        .lineLimit(1)

      Text(QuotaFormatting.tokenCount(value))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct WidgetTokenPeriodRow: View {
  var summary: CodexUsagePeriodSummary

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(summary.period.title)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text(QuotaFormatting.tokenBreakdown(summary.metrics))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.65)
      }

      Spacer(minLength: 6)

      VStack(alignment: .trailing, spacing: 3) {
        Text(QuotaFormatting.tokenCount(summary.metrics.totalTokens))
          .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.58)

        Text("\(summary.requestCount)次")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct WidgetTokenLargeBoard: View {
  var summaries: [CodexUsagePeriodSummary]

  var body: some View {
    VStack(spacing: 0) {
      ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
        WidgetTokenLargeListRow(summary: summary)

        if index < summaries.count - 1 {
          Divider()
            .opacity(0.32)
            .padding(.vertical, summaries.count >= 5 ? 6 : 8)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}

private struct WidgetTokenLargeListRow: View {
  var summary: CodexUsagePeriodSummary

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 6) {
        Text(summary.period.title)
          .font(.callout.weight(.semibold))
          .lineLimit(1)

        Text(QuotaFormatting.tokenBreakdown(summary.metrics))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.62)
      }

      Spacer(minLength: 8)

      VStack(alignment: .trailing, spacing: 4) {
        Text(QuotaFormatting.tokenCount(summary.metrics.totalTokens))
          .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.56)

        Text("\(summary.requestCount)次")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct WidgetTokenPeriodBlock: View {
  var summary: CodexUsagePeriodSummary
  var layout: WidgetTokenPeriodLayout

  private var totalTokens: Int {
    summary.metrics.totalTokens
  }

  var body: some View {
    VStack(alignment: .leading, spacing: spacing) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(summary.period.title)
          .font(titleFont)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Spacer(minLength: 0)

        if layout != .compact {
          Text("\(summary.requestCount)次")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(QuotaFormatting.tokenCount(totalTokens))
          .font(totalFont)
          .lineLimit(1)
          .minimumScaleFactor(0.55)

        if layout != .compact {
          Text("tokens")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }

      if layout != .compact {
        Text(QuotaFormatting.tokenBreakdown(summary.metrics))
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(layout == .tile ? 1 : 2)
          .minimumScaleFactor(0.62)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var spacing: CGFloat {
    switch layout {
    case .compact:
      5
    case .medium:
      7
    case .tile:
      6
    }
  }

  private var titleFont: Font {
    switch layout {
    case .compact:
      .caption2.weight(.semibold)
    default:
      .caption.weight(.semibold)
    }
  }

  private var totalFont: Font {
    switch layout {
    case .compact:
      .system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
    case .medium:
      .system(size: 24, weight: .semibold, design: .rounded).monospacedDigit()
    case .tile:
      .system(size: 23, weight: .semibold, design: .rounded).monospacedDigit()
    }
  }
}

@main
struct CodexQuotaWidgetBundle: WidgetBundle {
  var body: some Widget {
    CodexQuotaWidget()
  }
}

private extension CodexLocalUsageSummary {
  static func widgetPreview(now: Date = Date()) -> CodexLocalUsageSummary {
    CodexLocalUsageSummary(
      periods: [
        CodexUsagePeriodSummary(
          period: .today,
          metrics: CodexTokenMetrics(inputTokens: 182_000, outputTokens: 41_000, reasoningOutputTokens: 73_000, cachedInputTokens: 96_000, totalTokens: 392_000),
          requestCount: 28,
          sessionCount: 5
        ),
        CodexUsagePeriodSummary(
          period: .yesterday,
          metrics: CodexTokenMetrics(inputTokens: 148_000, outputTokens: 36_000, reasoningOutputTokens: 62_000, cachedInputTokens: 81_000, totalTokens: 327_000),
          requestCount: 24,
          sessionCount: 4
        ),
        CodexUsagePeriodSummary(
          period: .last7Days,
          metrics: CodexTokenMetrics(inputTokens: 823_000, outputTokens: 212_000, reasoningOutputTokens: 341_000, cachedInputTokens: 520_000, totalTokens: 1_896_000),
          requestCount: 131,
          sessionCount: 19
        ),
        CodexUsagePeriodSummary(
          period: .last30Days,
          metrics: CodexTokenMetrics(inputTokens: 2_840_000, outputTokens: 733_000, reasoningOutputTokens: 1_120_000, cachedInputTokens: 1_904_000, totalTokens: 6_597_000),
          requestCount: 428,
          sessionCount: 67
        ),
        CodexUsagePeriodSummary(
          period: .allTime,
          metrics: CodexTokenMetrics(inputTokens: 4_960_000, outputTokens: 1_108_000, reasoningOutputTokens: 1_871_000, cachedInputTokens: 3_480_000, totalTokens: 11_419_000),
          requestCount: 731,
          sessionCount: 102
        ),
      ],
      codexDirectory: "~/.codex",
      scannedFileCount: 120,
      parsedFileCount: 120,
      cacheHitFileCount: 0,
      parsedEventCount: 731,
      latestEventAt: now,
      generatedAt: now
    )
  }
}

private extension Array where Element == CodexUsagePeriod {
  func uniqued() -> [CodexUsagePeriod] {
    var seen = Set<CodexUsagePeriod>()
    return filter { seen.insert($0).inserted }
  }
}
