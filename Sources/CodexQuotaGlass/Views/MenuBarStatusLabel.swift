import AppKit
import CodexQuotaKit
import SwiftUI

struct MenuBarStatusLabel: View {
  var snapshot: QuotaSnapshot

  var body: some View {
    Image(nsImage: MenuBarStatusImageRenderer.image(for: snapshot))
      .resizable()
      .interpolation(.high)
    .frame(width: 34, height: 22, alignment: .center)
    .help(helpText)
    .accessibilityLabel(helpText)
  }

  private var helpText: String {
    guard !snapshot.isPlaceholder else {
      return "Codex Quota：去登录"
    }

    let fiveHourReset = QuotaFormatting.resetClock(snapshot.fiveHour.resetsAt)

    return "Codex 5 小时额度：剩余 \(QuotaFormatting.percent(snapshot.fiveHour.remainingPercent))，重置 \(fiveHourReset)"
  }
}

private enum MenuBarStatusImageRenderer {
  private static let size = NSSize(width: 34, height: 22)
  private static let barFrame = NSRect(x: 1, y: 15, width: 32, height: 5)
  private static let textFrame = NSRect(x: 0, y: 1, width: 34, height: 11)

  static func image(for snapshot: QuotaSnapshot) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    if snapshot.isPlaceholder {
      drawLoginText()
    } else {
      drawQuotaBar(fraction: snapshot.fiveHour.remainingFraction)
      drawResetText(QuotaFormatting.resetClock(snapshot.fiveHour.resetsAt))
    }

    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  private static func drawQuotaBar(fraction: Double) {
    let clamped = min(1, max(0, fraction))
    let fillWidth = max(barFrame.height, barFrame.width * clamped)
    let radius = barFrame.height / 2

    NSColor.black.withAlphaComponent(0.20).setFill()
    NSBezierPath(roundedRect: barFrame, xRadius: radius, yRadius: radius).fill()

    NSColor.black.withAlphaComponent(0.92).setFill()
    NSBezierPath(
      roundedRect: NSRect(
        x: barFrame.minX,
        y: barFrame.minY,
        width: fillWidth,
        height: barFrame.height
      ),
      xRadius: radius,
      yRadius: radius
    ).fill()
  }

  private static func drawResetText(_ text: String) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
      .foregroundColor: NSColor.black,
      .paragraphStyle: paragraphStyle,
    ]

    (text as NSString).draw(in: textFrame, withAttributes: attributes)
  }

  private static func drawLoginText() {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
      .foregroundColor: NSColor.black,
      .paragraphStyle: paragraphStyle,
    ]

    ("去登录" as NSString).draw(in: NSRect(x: 0, y: 6, width: 34, height: 12), withAttributes: attributes)
  }
}
