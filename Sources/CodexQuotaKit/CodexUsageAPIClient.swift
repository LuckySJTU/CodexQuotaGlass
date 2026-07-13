import Foundation

public enum CodexUsageAPIClientError: Error, LocalizedError, Sendable {
  case invalidResponse
  case requestFailed(statusCode: Int, bodyPreview: String)
  case unauthorized(statusCode: Int, bodyPreview: String)
  case missingRateLimit
  case missingWindow(String)

  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      "Codex usage API returned a non-HTTP response."
    case .requestFailed(let statusCode, let bodyPreview):
      "Codex usage API request failed with HTTP \(statusCode): \(bodyPreview)"
    case .unauthorized(let statusCode, let bodyPreview):
      "Codex usage API rejected the current auth token with HTTP \(statusCode): \(bodyPreview)"
    case .missingRateLimit:
      "Codex usage API response did not contain rate_limit."
    case .missingWindow(let name):
      "Codex usage API response did not contain \(name)."
    }
  }
}

public struct CodexUsageAPIClient: Sendable {
  public var endpoint: URL
  public var tokenStore: CodexAuthTokenStore

  public init(
    endpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
    tokenStore: CodexAuthTokenStore = CodexAuthTokenStore()
  ) {
    self.endpoint = endpoint
    self.tokenStore = tokenStore
  }

  public func fetchSnapshot() async throws -> QuotaSnapshot {
    let authContext = try await tokenStore.authContext()
    let data = try await fetchUsageData(authContext: authContext)
    return try Self.snapshot(from: data, endpoint: endpoint)
  }

  private func fetchUsageData(authContext: CodexAuthContext) async throws -> Data {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("CodexQuotaGlass/0.1", forHTTPHeaderField: "User-Agent")
    Self.applyAuthHeaders(to: &request, authContext: authContext)

    var (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CodexUsageAPIClientError.invalidResponse
    }

    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
      let refreshedToken = try await tokenStore.refreshAccessToken()
      let refreshedAuth = try tokenStore.loadPrivateAuth()
      Self.applyAuthHeaders(
        to: &request,
        authContext: CodexAuthContext(
          accessToken: refreshedToken,
          accountID: refreshedAuth.tokens.accountID
        )
      )
      (data, response) = try await URLSession.shared.data(for: request)

      guard let retryResponse = response as? HTTPURLResponse else {
        throw CodexUsageAPIClientError.invalidResponse
      }

      guard (200..<300).contains(retryResponse.statusCode) else {
        let preview = String(decoding: data.prefix(180), as: UTF8.self)
        throw CodexUsageAPIClientError.unauthorized(
          statusCode: retryResponse.statusCode,
          bodyPreview: preview
        )
      }

      return data
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let preview = String(decoding: data.prefix(180), as: UTF8.self)
      throw CodexUsageAPIClientError.requestFailed(
        statusCode: httpResponse.statusCode,
        bodyPreview: preview
      )
    }

    return data
  }

  private static func applyAuthHeaders(to request: inout URLRequest, authContext: CodexAuthContext) {
    request.setValue("Bearer \(authContext.accessToken)", forHTTPHeaderField: "Authorization")

    if let accountID = authContext.accountID, !accountID.isEmpty {
      request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
    }
  }

  private static func snapshot(from data: Data, endpoint: URL) throws -> QuotaSnapshot {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          object["rate_limit"] is [String: Any]
    else {
      throw CodexUsageAPIClientError.missingRateLimit
    }

    let now = Date()
    let candidates = windowCandidates(from: object)
    guard !candidates.isEmpty else {
      throw CodexUsageAPIClientError.missingWindow("rate_limit windows")
    }

    return QuotaSnapshot(
      fiveHour: try Self.selectedWindow(
        from: candidates,
        kind: .fiveHour,
        now: now
      ),
      weekly: try Self.selectedWindow(
        from: candidates,
        kind: .weekly,
        now: now
      ),
      capturedAt: now,
      source: endpoint.absoluteString,
      planType: object["plan_type"] as? String,
      isPlaceholder: false
    )
  }

  private struct WindowCandidate {
    var dictionary: [String: Any]
    var limitName: String?
    var priority: Int
  }

  private static func windowCandidates(from object: [String: Any]) -> [WindowCandidate] {
    var candidates: [WindowCandidate] = []

    appendWindows(
      from: object["rate_limit"] as? [String: Any],
      limitName: nil,
      priority: 0,
      to: &candidates
    )

    if let additionalRateLimits = object["additional_rate_limits"] as? [[String: Any]] {
      for (index, additionalRateLimit) in additionalRateLimits.enumerated() {
        appendWindows(
          from: additionalRateLimit["rate_limit"] as? [String: Any],
          limitName: additionalRateLimit["limit_name"] as? String,
          priority: 10 + index,
          to: &candidates
        )
      }
    }

    return candidates
  }

  private static func appendWindows(
    from rateLimit: [String: Any]?,
    limitName: String?,
    priority: Int,
    to candidates: inout [WindowCandidate]
  ) {
    guard let rateLimit else {
      return
    }

    for key in ["primary_window", "secondary_window"] {
      guard let window = rateLimit[key] as? [String: Any] else {
        continue
      }

      candidates.append(WindowCandidate(dictionary: window, limitName: limitName, priority: priority))
    }
  }

  private static func selectedWindow(
    from candidates: [WindowCandidate],
    kind: RateLimitWindow.Kind,
    now: Date
  ) throws -> RateLimitWindow {
    let matchingCandidates = candidates
      .filter { candidate in
        guard let seconds = intValue(candidate.dictionary["limit_window_seconds"]) else {
          return false
        }

        return matchesWindowLength(seconds: seconds, kind: kind)
      }
      .sorted { left, right in
        let leftDistance = distanceFromExpectedWindow(left.dictionary, kind: kind)
        let rightDistance = distanceFromExpectedWindow(right.dictionary, kind: kind)

        if leftDistance != rightDistance {
          return leftDistance < rightDistance
        }

        return left.priority < right.priority
      }

    guard let selected = matchingCandidates.first else {
      return .unavailable(kind: kind, now: now)
    }

    return try Self.window(
      from: selected.dictionary,
      kind: kind,
      limitName: selected.limitName
    )
  }

  private static func matchesWindowLength(seconds: Int, kind: RateLimitWindow.Kind) -> Bool {
    switch kind {
    case .fiveHour:
      return seconds > 0 && seconds <= 6 * 60 * 60
    case .weekly:
      return seconds >= 5 * 24 * 60 * 60 && seconds <= 9 * 24 * 60 * 60
    }
  }

  private static func distanceFromExpectedWindow(
    _ dictionary: [String: Any],
    kind: RateLimitWindow.Kind
  ) -> Int {
    let seconds = intValue(dictionary["limit_window_seconds"]) ?? 0
    let expectedSeconds: Int

    switch kind {
    case .fiveHour:
      expectedSeconds = 5 * 60 * 60
    case .weekly:
      expectedSeconds = 7 * 24 * 60 * 60
    }

    return abs(seconds - expectedSeconds)
  }

  private static func window(
    from dictionary: [String: Any],
    kind: RateLimitWindow.Kind,
    limitName: String?
  ) throws -> RateLimitWindow {
    guard let usedPercent = doubleValue(dictionary["used_percent"]) else {
      throw CodexUsageAPIClientError.missingWindow("\(kind.rawValue).used_percent")
    }

    let windowSeconds = intValue(dictionary["limit_window_seconds"]) ?? expectedWindowSeconds(for: kind)
    let resetAtSeconds = doubleValue(dictionary["reset_at"])
    let resetAfterSeconds = doubleValue(dictionary["reset_after_seconds"])
    let resetsAt = resetAtSeconds
      .map { Date(timeIntervalSince1970: $0) } ??
      Date().addingTimeInterval(resetAfterSeconds ?? 0)

    return RateLimitWindow(
      kind: kind,
      usedPercent: usedPercent,
      windowMinutes: windowSeconds / 60,
      resetsAt: resetsAt,
      limitID: "codex",
      limitName: limitName
    )
  }

  private static func expectedWindowSeconds(for kind: RateLimitWindow.Kind) -> Int {
    switch kind {
    case .fiveHour:
      5 * 60 * 60
    case .weekly:
      7 * 24 * 60 * 60
    }
  }

  private static func doubleValue(_ value: Any?) -> Double? {
    switch value {
    case let value as Double:
      value
    case let value as Int:
      Double(value)
    case let value as NSNumber:
      value.doubleValue
    case let value as String:
      Double(value)
    default:
      nil
    }
  }

  private static func intValue(_ value: Any?) -> Int? {
    switch value {
    case let value as Int:
      value
    case let value as Double:
      Int(value)
    case let value as NSNumber:
      value.intValue
    case let value as String:
      Int(value)
    default:
      nil
    }
  }
}
