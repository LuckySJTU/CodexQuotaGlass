import CodexQuotaKit
import SwiftUI

struct QuotaMetricCard: View {
  var window: RateLimitWindow
  var resetText: String
  var subscriptionText: String?
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 10 : 14) {
      HStack(alignment: .firstTextBaseline) {
        Text(window.title)
          .font(compact ? .headline : .title3.weight(.semibold))

        Spacer()

        Text(resetText)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      if window.isAvailable {
        HStack(spacing: compact ? 12 : 16) {
          ZStack {
            RingMeter(value: window.remainingFraction, lineWidth: compact ? 6 : 8)
            Text(QuotaFormatting.percent(window.remainingPercent))
              .font((compact ? Font.callout : Font.title3).weight(.semibold).monospacedDigit())
          }
          .frame(width: compact ? 56 : 72, height: compact ? 56 : 72)

          VStack(alignment: .leading, spacing: 6) {
            quotaLabel

            ProgressView(value: window.remainingFraction)
              .tint(.cyan)

            usageFooter
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 6) {
          Text("当前接口未提供")
            .font((compact ? Font.callout : Font.title3).weight(.semibold))

          Text("新版 Codex App 暂未返回这个时间窗。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 56 : 72, alignment: .leading)
      }
    }
    .padding(compact ? 14 : 16)
    .quotaGlass(cornerRadius: compact ? 16 : 20)
  }

  @ViewBuilder
  private var quotaLabel: some View {
    if compact {
      Text("剩余")
        .font(.caption)
        .foregroundStyle(.secondary)
    } else {
      VStack(alignment: .leading, spacing: 2) {
        if let subscriptionText {
          Text(subscriptionText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        }

        Text("剩余")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var usageFooter: some View {
    if compact, let subscriptionText {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("已用 \(QuotaFormatting.percent(window.usedPercent))")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)

        Spacer(minLength: 0)

        Text(subscriptionText)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
    } else {
      Text("已用 \(QuotaFormatting.percent(window.usedPercent))")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
  }
}

struct WeeklyOnlyQuotaCard: View {
  var window: RateLimitWindow
  var resetText: String
  var subscriptionText: String?
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 12 : 16) {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 3) {
          Text("一周额度")
            .font(compact ? .headline : .title3.weight(.semibold))

          Text("新版 Codex App 已取消 5h 额度")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        }

        Spacer()

        Label(resetText, systemImage: "calendar")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .labelStyle(.titleAndIcon)
      }

      HStack(alignment: .lastTextBaseline, spacing: compact ? 10 : 14) {
        Text(QuotaFormatting.percent(window.remainingPercent))
          .font(.system(size: compact ? 42 : 58, weight: .semibold, design: .rounded).monospacedDigit())
          .lineLimit(1)
          .minimumScaleFactor(0.65)

        VStack(alignment: .leading, spacing: 3) {
          if let subscriptionText, !compact {
            Text(subscriptionText)
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.78)
          }

          Text("剩余")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

          usageFooter
        }

        Spacer(minLength: 0)
      }

      ProgressView(value: window.remainingFraction)
        .tint(.cyan)

      if !compact, let limitName = window.limitName {
        Text(limitName)
          .font(.caption2)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
      }
    }
    .padding(compact ? 14 : 18)
    .quotaGlass(cornerRadius: compact ? 16 : 20)
  }

  @ViewBuilder
  private var usageFooter: some View {
    if compact, let subscriptionText {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("已用 \(QuotaFormatting.percent(window.usedPercent))")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)

        Spacer(minLength: 0)

        Text(subscriptionText)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.72)
      }
    } else {
      Text("已用 \(QuotaFormatting.percent(window.usedPercent))")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
    }
  }
}

struct CodexQuotaVersionNotice: View {
  var compact = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Image(systemName: "info.circle")
        .font(compact ? .caption : .callout)
        .foregroundStyle(.secondary)

      Text("新版 Codex App 已取消 5h 额度，当前仅显示一周额度。")
        .font(compact ? .caption : .callout)
        .foregroundStyle(.secondary)
        .lineLimit(compact ? 2 : 1)
        .minimumScaleFactor(0.82)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(compact ? 10 : 12)
    .quotaGlass(cornerRadius: compact ? 14 : 16)
  }
}

enum MenuBarLocalUsagePeriodPreference {
  static let storageKey = "menuBarLocalUsagePeriods"
  static let defaultPeriods = CodexUsagePeriod.allCases
  static let defaultRawValue = rawValue(for: defaultPeriods)

  static func periods(from rawValue: String) -> [CodexUsagePeriod] {
    guard !rawValue.isEmpty else {
      return []
    }

    let selected = Set(
      rawValue
        .split(separator: ",")
        .compactMap { CodexUsagePeriod(rawValue: String($0)) }
    )

    return CodexUsagePeriod.allCases.filter { selected.contains($0) }
  }

  static func rawValue(for periods: [CodexUsagePeriod]) -> String {
    let selected = Set(periods)
    return CodexUsagePeriod.allCases
      .filter { selected.contains($0) }
      .map(\.rawValue)
      .joined(separator: ",")
  }
}

struct LocalUsageSummaryCard: View {
  var summary: CodexLocalUsageSummary
  var isRefreshing: Bool
  var compact = false
  var displayedPeriods: [CodexUsagePeriod]?

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 10 : 14) {
      header

      if summary.parsedEventCount == 0 {
        emptyState
      } else if compact {
        if periodSummaries.isEmpty {
          emptySelectionState
        } else {
          VStack(spacing: 8) {
            ForEach(periodSummaries) { period in
              LocalUsageCompactRow(summary: period)
            }
          }
        }
      } else {
        LocalUsageTable(summary: summary)
      }

      if !compact {
        footer
      }
    }
    .padding(compact ? 14 : 16)
    .quotaGlass(cornerRadius: compact ? 16 : 20)
  }

  private var periodSummaries: [CodexUsagePeriodSummary] {
    let periods = displayedPeriods ?? CodexUsagePeriod.allCases
    return periods.map { summary.summary(for: $0) }
  }

  private var header: some View {
    HStack(spacing: 8) {
      Image(systemName: "chart.bar.doc.horizontal")
        .foregroundStyle(.secondary)

      Text("本地 token 用量")
        .font(compact ? .headline : .title3.weight(.semibold))

      Spacer()

      if isRefreshing {
        ProgressView()
          .controlSize(.small)
      } else if let latestEventAt = summary.latestEventAt {
        Text(QuotaFormatting.capturedTime(latestEventAt))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("未找到 token_count 记录")
        .font(compact ? .caption : .callout)
        .foregroundStyle(.secondary)

      Text(summary.codexDirectory)
        .font(.caption2.monospaced())
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }

  private var emptySelectionState: some View {
    Text("未选择菜单栏展示周期")
      .font(.caption)
      .foregroundStyle(.secondary)
  }

  private var footer: some View {
    HStack(spacing: 8) {
      Text("扫描 \(summary.scannedFileCount) 个 session 文件")
      Text("·")
      Text("读取 \(summary.parsedFileCount)")
      Text("·")
      Text("缓存 \(summary.cacheHitFileCount)")
      Text("·")
      Text("\(summary.parsedEventCount) 条 token 记录")
      Text("·")
      Text(summary.codexDirectory)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }
}

private struct LocalUsageCompactRow: View {
  var summary: CodexUsagePeriodSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(summary.period.title)
          .font(.caption.weight(.semibold))

        Spacer()

        Text("\(summary.requestCount)次")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)

        Text(QuotaFormatting.tokenCount(summary.metrics.totalTokens))
          .font(.callout.weight(.semibold).monospacedDigit())
      }

      Text(QuotaFormatting.tokenBreakdown(summary.metrics))
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .padding(.vertical, 2)
  }
}

private struct LocalUsageTable: View {
  var summary: CodexLocalUsageSummary

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
      GridRow {
        tableHeader("范围")
        tableHeader("Total")
        tableHeader("Input")
        tableHeader("Output")
        tableHeader("Reason")
        tableHeader("Cache")
        tableHeader("调用")
        tableHeader("Session")
      }

      Divider()
        .gridCellUnsizedAxes(.horizontal)

      ForEach(summary.periods) { periodSummary in
        GridRow {
          Text(periodSummary.period.title)
            .font(.callout.weight(.semibold))

          metricText(periodSummary.metrics.totalTokens, prominent: true)
          metricText(periodSummary.metrics.inputTokens)
          metricText(periodSummary.metrics.outputTokens)
          metricText(periodSummary.metrics.reasoningOutputTokens)
          metricText(periodSummary.metrics.cachedInputTokens)

          Text("\(periodSummary.requestCount)")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)

          Text("\(periodSummary.sessionCount)")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func tableHeader(_ text: String) -> some View {
    Text(text)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
  }

  private func metricText(_ value: Int, prominent: Bool = false) -> some View {
    Text(QuotaFormatting.tokenCount(value))
      .font((prominent ? Font.callout.weight(.semibold) : Font.callout).monospacedDigit())
      .foregroundStyle(prominent ? .primary : .secondary)
  }
}
