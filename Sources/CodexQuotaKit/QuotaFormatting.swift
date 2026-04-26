import Foundation

public enum QuotaFormatting {
  public static func percent(_ value: Double) -> String {
    "\(Int(value.rounded()))%"
  }

  public static func resetClock(_ date: Date, calendar: Calendar = .current) -> String {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    let hour = components.hour ?? 0
    let minute = components.minute ?? 0
    return String(format: "%02d:%02d", hour, minute)
  }

  public static func resetDays(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
    if date <= now {
      return "现在"
    }

    let start = calendar.startOfDay(for: now)
    let target = calendar.startOfDay(for: date)
    let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0

    if days <= 0 {
      return "今日"
    }

    return "\(days)日后"
  }

  public static func capturedTime(_ date: Date, calendar: Calendar = .current) -> String {
    resetClock(date, calendar: calendar)
  }

  public static func compactMenuText(_ snapshot: QuotaSnapshot) -> String {
    "5h \(percent(snapshot.fiveHour.remainingPercent))  W \(percent(snapshot.weekly.remainingPercent))"
  }

  public static func compactControlText(_ snapshot: QuotaSnapshot) -> String {
    "5h \(percent(snapshot.fiveHour.remainingPercent)) / 周 \(percent(snapshot.weekly.remainingPercent))"
  }
}
