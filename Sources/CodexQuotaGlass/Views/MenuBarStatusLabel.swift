import AppKit
import CodexQuotaKit
import SwiftUI

enum MenuBarDisplayStyle: String, CaseIterable, Identifiable {
  case progressReset
  case batteryOnly
  case batteryPercentOutside
  case batteryPercentInside

  static let storageKey = "menuBarDisplayStyle"
  static let defaultStyle: MenuBarDisplayStyle = .progressReset

  var id: String { rawValue }

  var title: String {
    switch self {
    case .progressReset:
      "进度条 + 重置时间"
    case .batteryOnly:
      "电池：只显示剩余"
    case .batteryPercentOutside:
      "电池：百分比在外"
    case .batteryPercentInside:
      "电池：百分比在内"
    }
  }

  var imageSize: NSSize {
    switch self {
    case .progressReset:
      NSSize(width: 34, height: 22)
    case .batteryOnly:
      NSSize(width: 28, height: 16)
    case .batteryPercentOutside:
      NSSize(width: 54, height: 16)
    case .batteryPercentInside:
      NSSize(width: 36, height: 16)
    }
  }
}

struct MenuBarStatusLabel: View {
  @AppStorage(MenuBarDisplayStyle.storageKey) private var styleRawValue = MenuBarDisplayStyle.defaultStyle.rawValue

  var snapshot: QuotaSnapshot

  var body: some View {
    let style = MenuBarDisplayStyle(rawValue: styleRawValue) ?? .defaultStyle
    let imageSize = MenuBarStatusImageRenderer.imageSize(for: snapshot, style: style)

    Image(nsImage: MenuBarStatusImageRenderer.image(for: snapshot, style: style))
      .resizable()
      .interpolation(.high)
      .frame(width: imageSize.width, height: imageSize.height, alignment: .center)
      .help(helpText(style: style))
      .accessibilityLabel(helpText(style: style))
  }

  private func helpText(style: MenuBarDisplayStyle) -> String {
    guard !snapshot.isPlaceholder else {
      return "Codex Quota：去登录"
    }

    let window = snapshot.primaryDisplayWindow
    let resetText = resetText(for: window)

    return "Codex \(window.title)额度：剩余 \(QuotaFormatting.percent(window.remainingPercent))，重置 \(resetText)，菜单栏样式：\(style.title)"
  }

  private func resetText(for window: RateLimitWindow) -> String {
    switch window.kind {
    case .fiveHour:
      QuotaFormatting.resetClock(window.resetsAt)
    case .weekly:
      QuotaFormatting.resetDays(window.resetsAt)
    }
  }
}

private enum MenuBarStatusImageRenderer {
  private static let loginSize = NSSize(width: 34, height: 22)
  private static let barFrame = NSRect(x: 1, y: 15, width: 32, height: 5)
  private static let textFrame = NSRect(x: 0, y: 1, width: 34, height: 11)

  static func imageSize(for snapshot: QuotaSnapshot, style: MenuBarDisplayStyle) -> NSSize {
    snapshot.isPlaceholder ? loginSize : style.imageSize
  }

  static func image(for snapshot: QuotaSnapshot, style: MenuBarDisplayStyle) -> NSImage {
    let size = imageSize(for: snapshot, style: style)
    let image = NSImage(size: size)
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(origin: .zero, size: size).fill()

    if snapshot.isPlaceholder {
      drawLoginText(in: size)
    } else {
      let window = snapshot.primaryDisplayWindow
      let resetText = resetText(for: window)

      switch style {
      case .progressReset:
        drawQuotaBar(fraction: window.remainingFraction)
        drawResetText(resetText)
      case .batteryOnly:
        drawBattery(fraction: window.remainingFraction, in: NSRect(x: 1, y: 3, width: 25, height: 10))
      case .batteryPercentOutside:
        drawBattery(fraction: window.remainingFraction, in: NSRect(x: 1, y: 3, width: 25, height: 10))
        drawPercentText(QuotaFormatting.percent(window.remainingPercent), in: NSRect(x: 31, y: 1, width: 22, height: 13), fontSize: 10)
      case .batteryPercentInside:
        drawBattery(fraction: window.remainingFraction, in: NSRect(x: 1, y: 2, width: 32, height: 12), fillAlpha: 0.34)
        drawPercentText(QuotaFormatting.percent(window.remainingPercent), in: NSRect(x: 2, y: 2, width: 30, height: 12), fontSize: 8.5)
      }
    }

    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  private static func resetText(for window: RateLimitWindow) -> String {
    switch window.kind {
    case .fiveHour:
      QuotaFormatting.resetClock(window.resetsAt)
    case .weekly:
      QuotaFormatting.resetDays(window.resetsAt)
    }
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

  private static func drawBattery(
    fraction: Double,
    in rect: NSRect,
    fillAlpha: CGFloat = 0.88
  ) {
    let bodyWidth = rect.width - 3
    let bodyRect = NSRect(x: rect.minX, y: rect.minY, width: bodyWidth, height: rect.height)
    let capRect = NSRect(
      x: bodyRect.maxX + 1,
      y: rect.minY + rect.height * 0.31,
      width: 2,
      height: rect.height * 0.38
    )
    let corner = rect.height * 0.24
    let innerRect = bodyRect.insetBy(dx: 2, dy: 2)
    let clamped = min(1, max(0, fraction))
    let fillWidth = max(clamped > 0 ? 1.5 : 0, innerRect.width * clamped)

    NSColor.black.withAlphaComponent(0.88).setStroke()
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: corner, yRadius: corner)
    bodyPath.lineWidth = 1.2
    bodyPath.stroke()

    NSColor.black.withAlphaComponent(0.88).setFill()
    NSBezierPath(roundedRect: capRect, xRadius: 0.8, yRadius: 0.8).fill()

    guard fillWidth > 0 else {
      return
    }

    NSColor.black.withAlphaComponent(fillAlpha).setFill()
    NSBezierPath(
      roundedRect: NSRect(
        x: innerRect.minX,
        y: innerRect.minY,
        width: fillWidth,
        height: innerRect.height
      ),
      xRadius: max(1, innerRect.height / 2),
      yRadius: max(1, innerRect.height / 2)
    ).fill()
  }

  private static func drawPercentText(_ text: String, in rect: NSRect, fontSize: CGFloat) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
      .foregroundColor: NSColor.black,
      .paragraphStyle: paragraphStyle,
    ]

    (text as NSString).draw(in: rect, withAttributes: attributes)
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

  private static func drawLoginText(in size: NSSize) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
      .foregroundColor: NSColor.black,
      .paragraphStyle: paragraphStyle,
    ]

    ("去登录" as NSString).draw(
      in: NSRect(x: 0, y: (size.height - 12) / 2, width: size.width, height: 12),
      withAttributes: attributes
    )
  }
}
