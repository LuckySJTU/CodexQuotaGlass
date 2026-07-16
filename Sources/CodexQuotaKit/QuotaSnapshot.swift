import Foundation

public struct RateLimitWindow: Codable, Equatable, Identifiable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case fiveHour
    case weekly
  }

  public var id: Kind { kind }

  public var kind: Kind
  public var usedPercent: Double
  public var windowMinutes: Int
  public var resetsAt: Date
  public var limitID: String?
  public var limitName: String?

  public init(
    kind: Kind,
    usedPercent: Double,
    windowMinutes: Int,
    resetsAt: Date,
    limitID: String? = nil,
    limitName: String? = nil
  ) {
    self.kind = kind
    self.usedPercent = usedPercent
    self.windowMinutes = windowMinutes
    self.resetsAt = resetsAt
    self.limitID = limitID
    self.limitName = limitName
  }

  public var remainingPercent: Double {
    min(100, max(0, 100 - usedPercent))
  }

  public var isAvailable: Bool {
    windowMinutes > 0 && limitID != "unavailable"
  }

  public var remainingFraction: Double {
    remainingPercent / 100
  }

  public var usedFraction: Double {
    min(1, max(0, usedPercent / 100))
  }

  public var title: String {
    switch kind {
    case .fiveHour:
      "5 小时"
    case .weekly:
      "一周"
    }
  }

  public var compactTitle: String {
    switch kind {
    case .fiveHour:
      "5h"
    case .weekly:
      "周"
    }
  }

  public static func unavailable(
    kind: Kind,
    now: Date = Date(),
    limitName: String? = nil
  ) -> RateLimitWindow {
    RateLimitWindow(
      kind: kind,
      usedPercent: 100,
      windowMinutes: 0,
      resetsAt: now,
      limitID: "unavailable",
      limitName: limitName
    )
  }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
  public var fiveHour: RateLimitWindow
  public var weekly: RateLimitWindow
  public var capturedAt: Date
  public var source: String
  public var planType: String?
  public var subscriptionPlan: String?
  public var isPlaceholder: Bool

  public init(
    fiveHour: RateLimitWindow,
    weekly: RateLimitWindow,
    capturedAt: Date,
    source: String,
    planType: String? = nil,
    subscriptionPlan: String? = nil,
    isPlaceholder: Bool = false
  ) {
    self.fiveHour = fiveHour
    self.weekly = weekly
    self.capturedAt = capturedAt
    self.source = source
    self.planType = planType
    self.subscriptionPlan = subscriptionPlan
    self.isPlaceholder = isPlaceholder
  }

  public static func placeholder(now: Date = Date()) -> QuotaSnapshot {
    QuotaSnapshot(
      fiveHour: RateLimitWindow(
        kind: .fiveHour,
        usedPercent: 24,
        windowMinutes: 300,
        resetsAt: now.addingTimeInterval(94 * 60),
        limitID: "codex"
      ),
      weekly: RateLimitWindow(
        kind: .weekly,
        usedPercent: 38,
        windowMinutes: 10_080,
        resetsAt: now.addingTimeInterval(4.2 * 24 * 60 * 60),
        limitID: "codex"
      ),
      capturedAt: now,
      source: "preview",
      isPlaceholder: true
    )
  }

  public var availableWindows: [RateLimitWindow] {
    [fiveHour, weekly].filter(\.isAvailable)
  }

  public var primaryDisplayWindow: RateLimitWindow {
    if fiveHour.isAvailable {
      return fiveHour
    }

    return weekly.isAvailable ? weekly : fiveHour
  }

  public var secondaryDisplayWindow: RateLimitWindow? {
    if fiveHour.isAvailable && weekly.isAvailable {
      return weekly
    }

    return nil
  }

  public var subscriptionDisplayName: String {
    CodexAccountInfo.displayPlanName(
      planType: planType,
      subscriptionPlan: subscriptionPlan,
      workspaceType: nil,
      hasActiveSubscription: nil
    )
  }
}
