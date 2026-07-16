import Foundation

public enum CodexAccountAPIClientError: Error, LocalizedError, Sendable {
  case invalidResponse
  case requestFailed(statusCode: Int, bodyPreview: String)
  case unauthorized(statusCode: Int, bodyPreview: String)
  case missingAccount

  public var errorDescription: String? {
    switch self {
    case .invalidResponse:
      "Codex account API returned a non-HTTP response."
    case .requestFailed(let statusCode, let bodyPreview):
      "Codex account API request failed with HTTP \(statusCode): \(bodyPreview)"
    case .unauthorized(let statusCode, let bodyPreview):
      "Codex account API rejected the current auth token with HTTP \(statusCode): \(bodyPreview)"
    case .missingAccount:
      "Codex account API response did not contain a usable account entry."
    }
  }
}

public struct CodexAccountInfo: Codable, Equatable, Sendable {
  public var planType: String?
  public var subscriptionPlan: String?
  public var billingPeriod: String?
  public var billingCurrency: String?
  public var hasActiveSubscription: Bool?
  public var isActiveSubscriptionGratis: Bool?
  public var accountUserRole: String?
  public var workspaceType: String?
  public var capturedAt: Date
  public var source: String

  public init(
    planType: String? = nil,
    subscriptionPlan: String? = nil,
    billingPeriod: String? = nil,
    billingCurrency: String? = nil,
    hasActiveSubscription: Bool? = nil,
    isActiveSubscriptionGratis: Bool? = nil,
    accountUserRole: String? = nil,
    workspaceType: String? = nil,
    capturedAt: Date = Date(),
    source: String
  ) {
    self.planType = planType
    self.subscriptionPlan = subscriptionPlan
    self.billingPeriod = billingPeriod
    self.billingCurrency = billingCurrency
    self.hasActiveSubscription = hasActiveSubscription
    self.isActiveSubscriptionGratis = isActiveSubscriptionGratis
    self.accountUserRole = accountUserRole
    self.workspaceType = workspaceType
    self.capturedAt = capturedAt
    self.source = source
  }

  public static func fallback(
    planType: String,
    capturedAt: Date = Date(),
    source: String
  ) -> CodexAccountInfo {
    CodexAccountInfo(
      planType: planType,
      capturedAt: capturedAt,
      source: source
    )
  }

  public var displayPlanName: String {
    subscriptionKind.displayName
  }

  public var subscriptionKind: CodexSubscriptionKind {
    Self.subscriptionKind(
      planType: planType,
      subscriptionPlan: subscriptionPlan,
      workspaceType: workspaceType,
      hasActiveSubscription: hasActiveSubscription,
      isActiveSubscriptionGratis: isActiveSubscriptionGratis
    )
  }

  public var rawSummaryText: String {
    var parts: [String] = []

    if let planType, !planType.isEmpty {
      parts.append("plan_type=\(planType)")
    }

    if let subscriptionPlan, !subscriptionPlan.isEmpty {
      parts.append("subscription_plan=\(subscriptionPlan)")
    }

    if let billingPeriod, !billingPeriod.isEmpty {
      parts.append("billing=\(billingPeriod)")
    }

    if let billingCurrency, !billingCurrency.isEmpty {
      parts.append(billingCurrency)
    }

    if let hasActiveSubscription {
      parts.append(hasActiveSubscription ? "active" : "inactive")
    }

    return parts.isEmpty ? "未返回订阅字段" : parts.joined(separator: " · ")
  }

  public static func displayPlanName(
    planType: String?,
    subscriptionPlan: String?,
    workspaceType: String?,
    hasActiveSubscription: Bool?,
    isActiveSubscriptionGratis: Bool? = nil
  ) -> String {
    subscriptionKind(
      planType: planType,
      subscriptionPlan: subscriptionPlan,
      workspaceType: workspaceType,
      hasActiveSubscription: hasActiveSubscription,
      isActiveSubscriptionGratis: isActiveSubscriptionGratis
    ).displayName
  }

  public static func subscriptionKind(
    planType: String?,
    subscriptionPlan: String?,
    workspaceType: String?,
    hasActiveSubscription: Bool?,
    isActiveSubscriptionGratis: Bool? = nil
  ) -> CodexSubscriptionKind {
    let values = [subscriptionPlan, planType, workspaceType]
      .compactMap { $0 }
      .map(normalizedPlanToken)

    if values.contains(where: { $0.contains("prolite") || $0.contains("pro5x") }) {
      return .pro5x
    }

    if values.contains(where: { $0.contains("pro20x") || $0.contains("promax") }) {
      return .pro20x
    }

    if values.contains(where: { $0 == "chatgptpro" || $0 == "pro" || $0.hasSuffix("pro") }) {
      return .pro20x
    }

    if values.contains(where: { $0.contains("plus") }) {
      return .plus
    }

    if values.contains(where: { $0 == "go" || $0.contains("chatgptgo") }) {
      return .go
    }

    if values.contains(where: { $0.contains("business") || $0.contains("team") }) {
      return .business
    }

    if values.contains(where: { $0.contains("enterprise") }) {
      return .enterprise
    }

    if values.contains(where: { $0.contains("edu") || $0.contains("student") }) {
      return .edu
    }

    if values.contains(where: { $0.contains("free") }) {
      return .free
    }

    if hasActiveSubscription == false || isActiveSubscriptionGratis == true {
      return .free
    }

    return .unknown
  }

  private static func normalizedPlanToken(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: "_", with: "")
      .replacingOccurrences(of: " ", with: "")
  }
}

public enum CodexSubscriptionKind: String, Codable, Sendable {
  case free
  case go
  case plus
  case pro5x
  case pro20x
  case business
  case enterprise
  case edu
  case unknown

  public var displayName: String {
    switch self {
    case .free:
      "免费用户"
    case .go:
      "GPT Air"
    case .plus:
      "GPT标准版"
    case .pro5x:
      "GPT Pro"
    case .pro20x:
      "GPT ProMax"
    case .business:
      "GPT团伙"
    case .enterprise:
      "GPT企业"
    case .edu:
      "教育优惠"
    case .unknown:
      "未知订阅"
    }
  }
}

public struct CodexAccountAPIClient: Sendable {
  public var endpoint: URL
  public var tokenStore: CodexAuthTokenStore

  public init(
    endpoint: URL = URL(string: "https://chatgpt.com/backend-api/accounts/check/v4-2023-04-27")!,
    tokenStore: CodexAuthTokenStore = CodexAuthTokenStore()
  ) {
    self.endpoint = endpoint
    self.tokenStore = tokenStore
  }

  public func fetchAccountInfo() async throws -> CodexAccountInfo {
    let authContext = try await tokenStore.authContext()
    let data = try await fetchAccountData(authContext: authContext)
    return try Self.accountInfo(from: data, endpoint: endpoint, authContext: authContext)
  }

  private func fetchAccountData(authContext: CodexAuthContext) async throws -> Data {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("CodexQuotaGlass/0.1", forHTTPHeaderField: "User-Agent")
    Self.applyAuthHeaders(to: &request, authContext: authContext)

    var (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CodexAccountAPIClientError.invalidResponse
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
        throw CodexAccountAPIClientError.invalidResponse
      }

      guard (200..<300).contains(retryResponse.statusCode) else {
        let preview = String(decoding: data.prefix(180), as: UTF8.self)
        throw CodexAccountAPIClientError.unauthorized(
          statusCode: retryResponse.statusCode,
          bodyPreview: preview
        )
      }

      return data
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let preview = String(decoding: data.prefix(180), as: UTF8.self)
      throw CodexAccountAPIClientError.requestFailed(
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

  private static func accountInfo(
    from data: Data,
    endpoint: URL,
    authContext: CodexAuthContext
  ) throws -> CodexAccountInfo {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let accountEntry = selectedAccountEntry(from: object, authContext: authContext)
    else {
      throw CodexAccountAPIClientError.missingAccount
    }

    let account = accountEntry["account"] as? [String: Any]
    let entitlement = accountEntry["entitlement"] as? [String: Any]

    return CodexAccountInfo(
      planType: stringValue(account?["plan_type"]),
      subscriptionPlan: stringValue(entitlement?["subscription_plan"]),
      billingPeriod: stringValue(entitlement?["billing_period"]),
      billingCurrency: stringValue(entitlement?["billing_currency"]),
      hasActiveSubscription: boolValue(entitlement?["has_active_subscription"]),
      isActiveSubscriptionGratis: boolValue(entitlement?["is_active_subscription_gratis"]),
      accountUserRole: stringValue(account?["account_user_role"]),
      workspaceType: stringValue(account?["workspace_type"]),
      capturedAt: Date(),
      source: endpoint.absoluteString
    )
  }

  private static func selectedAccountEntry(
    from object: [String: Any],
    authContext: CodexAuthContext
  ) -> [String: Any]? {
    guard let accounts = object["accounts"] as? [String: Any] else {
      return nil
    }

    if let accountID = authContext.accountID,
       let selected = accounts[accountID] as? [String: Any] {
      return selected
    }

    if let selected = accounts["default"] as? [String: Any] {
      return selected
    }

    if let ordering = object["account_ordering"] as? [String] {
      for accountID in ordering {
        if let selected = accounts[accountID] as? [String: Any] {
          return selected
        }
      }
    }

    return accounts.values.compactMap { $0 as? [String: Any] }.first
  }

  private static func stringValue(_ value: Any?) -> String? {
    switch value {
    case let value as String where !value.isEmpty:
      value
    case let value as NSNumber:
      value.stringValue
    default:
      nil
    }
  }

  private static func boolValue(_ value: Any?) -> Bool? {
    switch value {
    case let value as Bool:
      value
    case let value as NSNumber:
      value.boolValue
    case let value as String:
      switch value.lowercased() {
      case "true", "1", "yes":
        true
      case "false", "0", "no":
        false
      default:
        nil
      }
    default:
      nil
    }
  }
}
