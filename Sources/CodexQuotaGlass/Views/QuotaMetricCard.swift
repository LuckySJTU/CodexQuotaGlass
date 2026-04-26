import CodexQuotaKit
import SwiftUI

struct QuotaMetricCard: View {
  var window: RateLimitWindow
  var resetText: String
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

      HStack(spacing: compact ? 12 : 16) {
        ZStack {
          RingMeter(value: window.remainingFraction, lineWidth: compact ? 6 : 8)
          Text(QuotaFormatting.percent(window.remainingPercent))
            .font((compact ? Font.callout : Font.title3).weight(.semibold).monospacedDigit())
        }
        .frame(width: compact ? 56 : 72, height: compact ? 56 : 72)

        VStack(alignment: .leading, spacing: 6) {
          Text("剩余")
            .font(.caption)
            .foregroundStyle(.secondary)

          ProgressView(value: window.remainingFraction)
            .tint(.cyan)

          Text("已用 \(QuotaFormatting.percent(window.usedPercent))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(compact ? 14 : 16)
    .quotaGlass(cornerRadius: compact ? 16 : 20)
  }
}
