import Foundation

public enum CodexUsagePeriod: String, CaseIterable, Codable, Identifiable, Sendable {
  case today
  case yesterday
  case last7Days
  case last30Days
  case allTime

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .today:
      "今日"
    case .yesterday:
      "昨日"
    case .last7Days:
      "过去7天"
    case .last30Days:
      "过去30天"
    case .allTime:
      "有史以来"
    }
  }
}

public struct CodexTokenMetrics: Codable, Hashable, Sendable {
  public var inputTokens: Int
  public var outputTokens: Int
  public var reasoningOutputTokens: Int
  public var cachedInputTokens: Int
  public var totalTokens: Int

  public init(
    inputTokens: Int = 0,
    outputTokens: Int = 0,
    reasoningOutputTokens: Int = 0,
    cachedInputTokens: Int = 0,
    totalTokens: Int = 0
  ) {
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.reasoningOutputTokens = reasoningOutputTokens
    self.cachedInputTokens = cachedInputTokens
    self.totalTokens = totalTokens
  }

  public var hasUsage: Bool {
    inputTokens > 0 || outputTokens > 0 || reasoningOutputTokens > 0 || cachedInputTokens > 0 || totalTokens > 0
  }

  public mutating func add(_ other: CodexTokenMetrics) {
    inputTokens += other.inputTokens
    outputTokens += other.outputTokens
    reasoningOutputTokens += other.reasoningOutputTokens
    cachedInputTokens += other.cachedInputTokens
    totalTokens += other.totalTokens
  }

  public func subtracting(_ other: CodexTokenMetrics) -> CodexTokenMetrics {
    CodexTokenMetrics(
      inputTokens: max(0, inputTokens - other.inputTokens),
      outputTokens: max(0, outputTokens - other.outputTokens),
      reasoningOutputTokens: max(0, reasoningOutputTokens - other.reasoningOutputTokens),
      cachedInputTokens: max(0, cachedInputTokens - other.cachedInputTokens),
      totalTokens: max(0, totalTokens - other.totalTokens)
    )
  }
}

public struct CodexUsagePeriodSummary: Codable, Equatable, Identifiable, Sendable {
  public var id: CodexUsagePeriod { period }

  public var period: CodexUsagePeriod
  public var metrics: CodexTokenMetrics
  public var requestCount: Int
  public var sessionCount: Int

  public init(
    period: CodexUsagePeriod,
    metrics: CodexTokenMetrics = CodexTokenMetrics(),
    requestCount: Int = 0,
    sessionCount: Int = 0
  ) {
    self.period = period
    self.metrics = metrics
    self.requestCount = requestCount
    self.sessionCount = sessionCount
  }
}

public struct CodexLocalUsageSummary: Codable, Equatable, Sendable {
  public var periods: [CodexUsagePeriodSummary]
  public var codexDirectory: String
  public var scannedFileCount: Int
  public var parsedFileCount: Int
  public var cacheHitFileCount: Int
  public var parsedEventCount: Int
  public var latestEventAt: Date?
  public var generatedAt: Date

  public init(
    periods: [CodexUsagePeriodSummary],
    codexDirectory: String,
    scannedFileCount: Int,
    parsedFileCount: Int,
    cacheHitFileCount: Int,
    parsedEventCount: Int,
    latestEventAt: Date?,
    generatedAt: Date
  ) {
    self.periods = periods
    self.codexDirectory = codexDirectory
    self.scannedFileCount = scannedFileCount
    self.parsedFileCount = parsedFileCount
    self.cacheHitFileCount = cacheHitFileCount
    self.parsedEventCount = parsedEventCount
    self.latestEventAt = latestEventAt
    self.generatedAt = generatedAt
  }

  public static func empty(
    codexDirectory: String = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".codex").path,
    now: Date = Date()
  ) -> CodexLocalUsageSummary {
    CodexLocalUsageSummary(
      periods: CodexUsagePeriod.allCases.map { CodexUsagePeriodSummary(period: $0) },
      codexDirectory: codexDirectory,
      scannedFileCount: 0,
      parsedFileCount: 0,
      cacheHitFileCount: 0,
      parsedEventCount: 0,
      latestEventAt: nil,
      generatedAt: now
    )
  }

  public func summary(for period: CodexUsagePeriod) -> CodexUsagePeriodSummary {
    periods.first { $0.period == period } ?? CodexUsagePeriodSummary(period: period)
  }
}

public final class CodexLocalUsageProvider: @unchecked Sendable {
  private let codexDirectory: URL
  private let fileManager: FileManager
  private let isoFormatter: ISO8601DateFormatter
  private var sessionCache: [String: CachedSessionUsage] = [:]

  public init(
    codexDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"),
    fileManager: FileManager = .default
  ) {
    self.codexDirectory = codexDirectory
    self.fileManager = fileManager
    isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  }

  public func loadSummary(now: Date = Date(), calendar: Calendar = .current) async -> CodexLocalUsageSummary {
    let windows = UsageWindows(now: now, calendar: calendar)
    var summaries = Dictionary(
      uniqueKeysWithValues: CodexUsagePeriod.allCases.map {
        ($0, MutablePeriodSummary(period: $0))
      }
    )

    let files = sessionFiles()
    let activeCacheKeys = Set(files.map(\.cacheKey))
    sessionCache = sessionCache.filter { activeCacheKeys.contains($0.key) }

    var sessionsByID: [String: CodexSessionUsage] = [:]
    var parsedFileCount = 0
    var cacheHitFileCount = 0
    var parsedEventCount = 0
    var latestEventAt: Date?

    for file in files {
      do {
        let session: CodexSessionUsage
        if let cached = sessionCache[file.cacheKey], cached.signature == file.signature {
          session = cached.session
          cacheHitFileCount += 1
        } else {
          session = try await tokenSession(in: file.url)
          sessionCache[file.cacheKey] = CachedSessionUsage(signature: file.signature, session: session)
          parsedFileCount += 1
        }

        guard !session.events.isEmpty else {
          continue
        }

        if let existing = sessionsByID[session.id], existing.sortScore >= session.sortScore {
          continue
        }

        sessionsByID[session.id] = session
      } catch {
        continue
      }
    }

    for session in sessionsByID.values {
      for event in session.events {
        guard event.timestamp < windows.tomorrowStart else {
          continue
        }

        parsedEventCount += 1
        if latestEventAt == nil || event.timestamp > latestEventAt! {
          latestEventAt = event.timestamp
        }

        for period in CodexUsagePeriod.allCases where windows.contains(event.timestamp, in: period) {
          summaries[period]?.add(event)
        }
      }
    }

    return CodexLocalUsageSummary(
      periods: CodexUsagePeriod.allCases.map { summaries[$0]?.frozen() ?? CodexUsagePeriodSummary(period: $0) },
      codexDirectory: codexDirectory.path,
      scannedFileCount: files.count,
      parsedFileCount: parsedFileCount,
      cacheHitFileCount: cacheHitFileCount,
      parsedEventCount: parsedEventCount,
      latestEventAt: latestEventAt,
      generatedAt: now
    )
  }

  private func sessionFiles() -> [CodexLogFile] {
    let roots = [
      codexDirectory.appendingPathComponent("sessions", isDirectory: true),
      codexDirectory.appendingPathComponent("archived_sessions", isDirectory: true),
    ]
    var files: [CodexLogFile] = []

    for root in roots where fileManager.fileExists(atPath: root.path) {
      guard let enumerator = fileManager.enumerator(
        at: root,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
      ) else {
        continue
      }

      for case let file as URL in enumerator {
        guard file.pathExtension == "jsonl" else {
          continue
        }

        guard let logFile = codexLogFile(for: file) else {
          continue
        }

        files.append(logFile)
      }
    }

    return files.sorted { $0.url.path < $1.url.path }
  }

  private func tokenSession(in file: URL) async throws -> CodexSessionUsage {
    var sessionID = file.deletingPathExtension().lastPathComponent
    var previousTotal: CodexTokenMetrics?
    var seenTotalMetrics = Set<CodexTokenMetrics>()
    var events: [CodexUsageEvent] = []

    for try await line in file.lines {
      guard line.contains("\"token_count\"") || line.contains("\"session_meta\"") else {
        continue
      }

      guard
        let data = line.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let type = object["type"] as? String
      else {
        continue
      }

      if type == "session_meta" {
        if
          let payload = object["payload"] as? [String: Any],
          let id = payload["id"] as? String,
          !id.isEmpty
        {
          sessionID = id
        }
        continue
      }

      guard
        type == "event_msg",
        let payload = object["payload"] as? [String: Any],
        payload["type"] as? String == "token_count",
        let timestampText = object["timestamp"] as? String,
        let timestamp = isoFormatter.date(from: timestampText),
        let info = payload["info"] as? [String: Any]
      else {
        continue
      }

      let total = metrics(from: info["total_token_usage"])
      let last = metrics(from: info["last_token_usage"])

      if let total, !seenTotalMetrics.insert(total).inserted {
        continue
      }

      let increment = usageIncrement(total: total, last: last, previousTotal: &previousTotal)

      guard increment.hasUsage else {
        continue
      }

      events.append(
        CodexUsageEvent(
          timestamp: timestamp,
          sessionID: sessionID,
          metrics: increment
        )
      )
    }

    return CodexSessionUsage(id: sessionID, events: events)
  }

  private func usageIncrement(
    total: CodexTokenMetrics?,
    last: CodexTokenMetrics?,
    previousTotal: inout CodexTokenMetrics?
  ) -> CodexTokenMetrics {
    guard let total else {
      return last ?? CodexTokenMetrics()
    }

    defer {
      previousTotal = total
    }

    if let last, last.hasUsage {
      return last
    }

    guard let previousTotal else {
      return total
    }

    if total.totalTokens >= previousTotal.totalTokens {
      return total.subtracting(previousTotal)
    }

    return last ?? total
  }

  private func metrics(from value: Any?) -> CodexTokenMetrics? {
    guard let object = value as? [String: Any] else {
      return nil
    }

    return CodexTokenMetrics(
      inputTokens: intValue(object["input_tokens"]),
      outputTokens: intValue(object["output_tokens"]),
      reasoningOutputTokens: intValue(object["reasoning_output_tokens"]),
      cachedInputTokens: intValue(object["cached_input_tokens"]),
      totalTokens: intValue(object["total_tokens"])
    )
  }

  private func intValue(_ value: Any?) -> Int {
    switch value {
    case let number as NSNumber:
      number.intValue
    case let int as Int:
      int
    case let string as String:
      Int(string) ?? 0
    default:
      0
    }
  }

  private func codexLogFile(for url: URL) -> CodexLogFile? {
    guard
      let resourceValues = try? url.resourceValues(forKeys: [
        .contentModificationDateKey,
        .fileSizeKey,
        .isRegularFileKey,
      ]),
      resourceValues.isRegularFile == true
    else {
      return nil
    }

    let signature = CodexLogFileSignature(
      byteCount: resourceValues.fileSize ?? 0,
      modifiedAt: resourceValues.contentModificationDate ?? .distantPast
    )

    return CodexLogFile(url: url, signature: signature)
  }
}

private struct UsageWindows {
  var todayStart: Date
  var tomorrowStart: Date
  var yesterdayStart: Date
  var last7Start: Date
  var last30Start: Date

  init(now: Date, calendar: Calendar) {
    todayStart = calendar.startOfDay(for: now)
    tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
    yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
    last7Start = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
    last30Start = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
  }

  func contains(_ date: Date, in period: CodexUsagePeriod) -> Bool {
    switch period {
    case .today:
      date >= todayStart && date < tomorrowStart
    case .yesterday:
      date >= yesterdayStart && date < todayStart
    case .last7Days:
      date >= last7Start && date < tomorrowStart
    case .last30Days:
      date >= last30Start && date < tomorrowStart
    case .allTime:
      date < tomorrowStart
    }
  }
}

private struct CodexLogFile {
  var url: URL
  var signature: CodexLogFileSignature

  var cacheKey: String {
    url.path
  }
}

private struct CodexLogFileSignature: Equatable {
  var byteCount: Int
  var modifiedAt: Date
}

private struct CodexUsageEvent {
  var timestamp: Date
  var sessionID: String
  var metrics: CodexTokenMetrics
}

private struct CodexSessionUsage {
  var id: String
  var events: [CodexUsageEvent]

  var sortScore: Int {
    events.reduce(0) { partialResult, event in
      partialResult + event.metrics.totalTokens
    }
  }
}

private struct CachedSessionUsage {
  var signature: CodexLogFileSignature
  var session: CodexSessionUsage
}

private struct MutablePeriodSummary {
  var period: CodexUsagePeriod
  var metrics = CodexTokenMetrics()
  var requestCount = 0
  var sessionIDs: Set<String> = []

  mutating func add(_ event: CodexUsageEvent) {
    metrics.add(event.metrics)
    requestCount += 1
    sessionIDs.insert(event.sessionID)
  }

  func frozen() -> CodexUsagePeriodSummary {
    CodexUsagePeriodSummary(
      period: period,
      metrics: metrics,
      requestCount: requestCount,
      sessionCount: sessionIDs.count
    )
  }
}
