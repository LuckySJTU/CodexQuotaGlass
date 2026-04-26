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
    let accessToken = try await tokenStore.accessToken()
    let data = try await fetchUsageData(accessToken: accessToken)
    return try Self.snapshot(from: data, endpoint: endpoint)
  }

  private func fetchUsageData(accessToken: String) async throws -> Data {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("CodexQuotaGlass/0.1", forHTTPHeaderField: "User-Agent")

    var (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CodexUsageAPIClientError.invalidResponse
    }

    if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
      let refreshedToken = try await tokenStore.refreshAccessToken()
      request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
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

  private static func snapshot(from data: Data, endpoint: URL) throws -> QuotaSnapshot {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let rateLimit = object["rate_limit"] as? [String: Any]
    else {
      throw CodexUsageAPIClientError.missingRateLimit
    }

    guard let primary = rateLimit["primary_window"] as? [String: Any] else {
      throw CodexUsageAPIClientError.missingWindow("primary_window")
    }

    guard let secondary = rateLimit["secondary_window"] as? [String: Any] else {
      throw CodexUsageAPIClientError.missingWindow("secondary_window")
    }

    return QuotaSnapshot(
      fiveHour: try Self.window(
        from: primary,
        kind: .fiveHour,
        fallbackWindowSeconds: 18_000
      ),
      weekly: try Self.window(
        from: secondary,
        kind: .weekly,
        fallbackWindowSeconds: 604_800
      ),
      capturedAt: Date(),
      source: endpoint.absoluteString,
      planType: object["plan_type"] as? String,
      isPlaceholder: false
    )
  }

  private static func window(
    from dictionary: [String: Any],
    kind: RateLimitWindow.Kind,
    fallbackWindowSeconds: Int
  ) throws -> RateLimitWindow {
    guard let usedPercent = doubleValue(dictionary["used_percent"]) else {
      throw CodexUsageAPIClientError.missingWindow("\(kind.rawValue).used_percent")
    }

    let windowSeconds = intValue(dictionary["limit_window_seconds"]) ?? fallbackWindowSeconds
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
      limitID: "codex"
    )
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
