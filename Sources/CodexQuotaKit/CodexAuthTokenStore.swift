@preconcurrency import CryptoKit
import Foundation
@preconcurrency import Network
import Security

public enum CodexAuthTokenStoreError: Error, LocalizedError, Sendable {
  case authFileMissing(URL)
  case invalidAuthFile(URL)
  case missingAccessToken(URL)
  case missingRefreshToken(URL)
  case tokenRefreshFailed(statusCode: Int, bodyPreview: String)
  case tokenExchangeFailed(statusCode: Int, bodyPreview: String)
  case callbackServerFailed(String)
  case callbackTimedOut
  case callbackStateMismatch
  case callbackRejected(String)
  case randomGenerationFailed(OSStatus)

  public var errorDescription: String? {
    switch self {
    case .authFileMissing(let url):
      "Codex Quota auth file was not found at \(url.path)."
    case .invalidAuthFile(let url):
      "Codex Quota auth file at \(url.path) could not be parsed."
    case .missingAccessToken(let url):
      "Codex Quota auth file at \(url.path) does not contain an access token."
    case .missingRefreshToken(let url):
      "Codex Quota auth file at \(url.path) does not contain a refresh token."
    case .tokenRefreshFailed(let statusCode, let bodyPreview):
      "Codex token refresh failed with HTTP \(statusCode): \(bodyPreview)"
    case .tokenExchangeFailed(let statusCode, let bodyPreview):
      "Codex web login token exchange failed with HTTP \(statusCode): \(bodyPreview)"
    case .callbackServerFailed(let reason):
      "Codex web login callback server failed: \(reason)"
    case .callbackTimedOut:
      "Codex web login timed out."
    case .callbackStateMismatch:
      "Codex web login returned an unexpected state."
    case .callbackRejected(let reason):
      "Codex web login was rejected: \(reason)"
    case .randomGenerationFailed(let status):
      "Secure random generation failed with status \(status)."
    }
  }
}

public struct CodexAuthTokens: Codable, Equatable, Sendable {
  public var idToken: String?
  public var accessToken: String
  public var refreshToken: String?
  public var accountID: String?

  public init(
    idToken: String? = nil,
    accessToken: String,
    refreshToken: String? = nil,
    accountID: String? = nil
  ) {
    self.idToken = idToken
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.accountID = accountID
  }

  enum CodingKeys: String, CodingKey {
    case idToken = "id_token"
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case accountID = "account_id"
  }
}

public struct CodexAuthFile: Codable, Equatable, Sendable {
  public var tokens: CodexAuthTokens
  public var lastRefresh: Date?

  public init(tokens: CodexAuthTokens, lastRefresh: Date? = nil) {
    self.tokens = tokens
    self.lastRefresh = lastRefresh
  }

  enum CodingKeys: String, CodingKey {
    case tokens
    case lastRefresh = "last_refresh"
  }
}

public struct CodexAuthContext: Equatable, Sendable {
  public var accessToken: String
  public var accountID: String?

  public init(accessToken: String, accountID: String? = nil) {
    self.accessToken = accessToken
    self.accountID = accountID
  }
}

public struct CodexAuthTokenStore: Sendable {
  public static let appSupportDirectoryName = "CodexQuotaGlass"
  public static let authFileName = "auth.json"
  public static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
  public static let tokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!

  public var authFileURL: URL
  public var importAuthFileURL: URL

  public init(
    authFileURL: URL = CodexAuthTokenStore.defaultAuthFileURL(),
    importAuthFileURL: URL = CodexAuthTokenStore.defaultCodexAuthFileURL()
  ) {
    self.authFileURL = authFileURL
    self.importAuthFileURL = importAuthFileURL
  }

  public init(homeDirectory: URL) {
    self.init(
      authFileURL: CodexAuthTokenStore.defaultAuthFileURL(fileManager: .default),
      importAuthFileURL: CodexAuthTokenStore.defaultCodexAuthFileURL(homeDirectory: homeDirectory)
    )
  }

  public static func defaultAuthFileURL(fileManager: FileManager = .default) -> URL {
    let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

    return supportURL
      .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
      .appendingPathComponent(authFileName, isDirectory: false)
  }

  public static func defaultCodexAuthFileURL(
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) -> URL {
    homeDirectory
      .appendingPathComponent(".codex", isDirectory: true)
      .appendingPathComponent("auth.json", isDirectory: false)
  }

  public var hasPrivateAuth: Bool {
    FileManager.default.fileExists(atPath: authFileURL.path)
  }

  public func accessToken() async throws -> String {
    let authFile = try loadPrivateAuthOrImportFromCodex()

    if Self.jwtExpiresSoon(authFile.tokens.accessToken) {
      return try await refreshAccessToken()
    }

    return authFile.tokens.accessToken
  }

  public func authContext() async throws -> CodexAuthContext {
    let accessToken = try await accessToken()
    let authFile = try loadPrivateAuth()
    return CodexAuthContext(
      accessToken: accessToken,
      accountID: authFile.tokens.accountID
    )
  }

  @discardableResult
  public func importFromCodexIfNeeded() throws -> Bool {
    guard !hasPrivateAuth else {
      return false
    }

    try importFromCodexAuth()
    return true
  }

  public func importFromCodexAuth() throws {
    let imported = try loadAuthFile(from: importAuthFileURL)
    try save(imported)
  }

  public func removePrivateAuth() throws {
    guard hasPrivateAuth else {
      return
    }

    try FileManager.default.removeItem(at: authFileURL)
  }

  @discardableResult
  public func refreshAccessToken() async throws -> String {
    let authFile = try loadPrivateAuthOrImportFromCodex()
    guard let refreshToken = authFile.tokens.refreshToken, !refreshToken.isEmpty else {
      throw CodexAuthTokenStoreError.missingRefreshToken(authFileURL)
    }

    let responseTokens = try await requestOAuthTokens(
      items: [
        ("grant_type", "refresh_token"),
        ("refresh_token", refreshToken),
        ("client_id", Self.clientID),
      ],
      failure: CodexAuthTokenStoreError.tokenRefreshFailed
    )

    let merged = CodexAuthTokens(
      idToken: responseTokens.idToken ?? authFile.tokens.idToken,
      accessToken: responseTokens.accessToken,
      refreshToken: responseTokens.refreshToken ?? refreshToken,
      accountID: responseTokens.accountID ?? authFile.tokens.accountID
    )

    try save(CodexAuthFile(tokens: merged, lastRefresh: Date()))
    return merged.accessToken
  }

  public func save(tokens: CodexAuthTokens) throws {
    try save(CodexAuthFile(tokens: tokens, lastRefresh: Date()))
  }

  public func save(_ authFile: CodexAuthFile) throws {
    let directoryURL = authFileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directoryURL.path
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(authFile)
    try data.write(to: authFileURL, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: authFileURL.path
    )
  }

  public func loadPrivateAuth() throws -> CodexAuthFile {
    try hardenPrivateAuthPermissionsIfPresent()
    return try loadAuthFile(from: authFileURL)
  }

  private func loadPrivateAuthOrImportFromCodex() throws -> CodexAuthFile {
    if hasPrivateAuth {
      return try loadPrivateAuth()
    }

    try importFromCodexAuth()
    return try loadPrivateAuth()
  }

  private func hardenPrivateAuthPermissionsIfPresent() throws {
    guard hasPrivateAuth else {
      return
    }

    let directoryURL = authFileURL.deletingLastPathComponent()
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700],
      ofItemAtPath: directoryURL.path
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600],
      ofItemAtPath: authFileURL.path
    )
  }

  private func loadAuthFile(from url: URL) throws -> CodexAuthFile {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw CodexAuthTokenStoreError.authFileMissing(url)
    }

    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .codexISO8601
      let authFile = try decoder.decode(CodexAuthFile.self, from: data)

      guard !authFile.tokens.accessToken.isEmpty else {
        throw CodexAuthTokenStoreError.missingAccessToken(url)
      }

      return authFile
    } catch let error as CodexAuthTokenStoreError {
      throw error
    } catch {
      throw CodexAuthTokenStoreError.invalidAuthFile(url)
    }
  }

  fileprivate func requestOAuthTokens(
    items: [(String, String)],
    failure: @escaping @Sendable (Int, String) -> CodexAuthTokenStoreError
  ) async throws -> CodexAuthTokens {
    var request = URLRequest(url: Self.tokenEndpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("CodexQuotaGlass/0.1", forHTTPHeaderField: "User-Agent")
    request.httpBody = Self.formBody(items)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw CodexAuthTokenStoreError.callbackServerFailed("token endpoint returned a non-HTTP response")
    }

    guard (200..<300).contains(httpResponse.statusCode) else {
      let preview = String(decoding: data.prefix(220), as: UTF8.self)
      throw failure(httpResponse.statusCode, preview)
    }

    let decoder = JSONDecoder()
    return try decoder.decode(CodexAuthTokens.self, from: data)
  }

  private static func formBody(_ items: [(String, String)]) -> Data {
    var components = URLComponents()
    components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
    return Data((components.percentEncodedQuery ?? "").utf8)
  }

  private static func jwtExpiresSoon(_ token: String, graceInterval: TimeInterval = 120) -> Bool {
    let parts = token.split(separator: ".")
    guard parts.count >= 2,
          let payloadData = Data(base64URLEncoded: String(parts[1])),
          let object = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
          let expiration = object["exp"] as? TimeInterval
    else {
      return false
    }

    return Date(timeIntervalSince1970: expiration).timeIntervalSinceNow <= graceInterval
  }
}

public struct CodexWebOAuthAuthenticator: Sendable {
  public var tokenStore: CodexAuthTokenStore
  public var authorizeEndpoint: URL
  public var scopes: String

  public init(
    tokenStore: CodexAuthTokenStore = CodexAuthTokenStore(),
    authorizeEndpoint: URL = URL(string: "https://auth.openai.com/oauth/authorize")!,
    scopes: String = "openid profile email offline_access"
  ) {
    self.tokenStore = tokenStore
    self.authorizeEndpoint = authorizeEndpoint
    self.scopes = scopes
  }

  public func authenticate(openURL: @escaping @Sendable (URL) -> Void) async throws {
    do {
      try await authenticate(scopes: scopes, openURL: openURL)
    } catch CodexAuthTokenStoreError.callbackRejected(let reason) where reason == "invalid_scope" {
      try await authenticate(scopes: "", openURL: openURL)
    } catch CodexAuthTokenStoreError.tokenExchangeFailed(_, let bodyPreview)
      where bodyPreview.contains("invalid_scope") {
      try await authenticate(scopes: "", openURL: openURL)
    }
  }

  private func authenticate(scopes: String, openURL: @escaping @Sendable (URL) -> Void) async throws {
    let state = try Self.randomBase64URL(byteCount: 32)
    let codeVerifier = try Self.randomBase64URL(byteCount: 64)
    let codeChallenge = Self.codeChallenge(for: codeVerifier)
    let callbackServer = try CodexOAuthCallbackServer(state: state, port: Self.callbackPort)
    let redirectURI = "http://localhost:\(callbackServer.port)/auth/callback"
    let authorizationURL = try authorizationURL(
      redirectURI: redirectURI,
      state: state,
      codeChallenge: codeChallenge,
      scopes: scopes
    )

    do {
      async let callbackCode = callbackServer.waitForAuthorizationCode()
      openURL(authorizationURL)
      let code = try await callbackCode

      let tokens = try await tokenStore.requestOAuthTokens(
        items: [
          ("grant_type", "authorization_code"),
          ("code", code),
          ("redirect_uri", redirectURI),
          ("client_id", CodexAuthTokenStore.clientID),
          ("code_verifier", codeVerifier),
        ],
        failure: CodexAuthTokenStoreError.tokenExchangeFailed
      )
      try tokenStore.save(tokens: tokens)
    } catch {
      callbackServer.cancel()
      throw error
    }
  }

  private func authorizationURL(
    redirectURI: String,
    state: String,
    codeChallenge: String,
    scopes: String
  ) throws -> URL {
    var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)
    var queryItems = [
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "client_id", value: CodexAuthTokenStore.clientID),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "code_challenge", value: codeChallenge),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "id_token_add_organizations", value: "true"),
      URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "originator", value: "Codex Quota Glass"),
    ]

    if !scopes.isEmpty {
      queryItems.insert(URLQueryItem(name: "scope", value: scopes), at: 3)
    }

    components?.queryItems = queryItems

    guard let url = components?.url else {
      throw CodexAuthTokenStoreError.callbackServerFailed("could not build authorization URL")
    }

    return url
  }

  private static func codeChallenge(for verifier: String) -> String {
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return Data(digest).base64URLEncodedString()
  }

  private static let callbackPort: UInt16 = 1455

  fileprivate static func randomBase64URL(byteCount: Int) throws -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    guard status == errSecSuccess else {
      throw CodexAuthTokenStoreError.randomGenerationFailed(status)
    }

    return Data(bytes).base64URLEncodedString()
  }
}

private final class CodexOAuthCallbackServer: @unchecked Sendable {
  private let listener: NWListener
  private let state: String
  private let queue = DispatchQueue(label: "CodexQuotaGlass.OAuthCallback")
  private let lock = NSLock()
  private var continuation: CheckedContinuation<String, Error>?
  private var finished = false

  let port: UInt16

  init(state: String, port requestedPort: UInt16? = nil) throws {
    self.state = state

    if let requestedPort {
      guard let endpointPort = NWEndpoint.Port(rawValue: requestedPort) else {
        throw CodexAuthTokenStoreError.callbackServerFailed("invalid local callback port \(requestedPort)")
      }

      do {
        listener = try NWListener(using: .tcp, on: endpointPort)
        port = requestedPort
        return
      } catch {
        throw CodexAuthTokenStoreError.callbackServerFailed(
          "local callback port \(requestedPort) is unavailable: \(error.localizedDescription)"
        )
      }
    }

    var lastError: Error?
    for _ in 0..<24 {
      let candidatePort = UInt16.random(in: 49_152...60_999)
      guard let endpointPort = NWEndpoint.Port(rawValue: candidatePort) else {
        continue
      }

      do {
        listener = try NWListener(using: .tcp, on: endpointPort)
        port = candidatePort
        return
      } catch {
        lastError = error
      }
    }

    throw CodexAuthTokenStoreError.callbackServerFailed(
      lastError?.localizedDescription ?? "no local callback port was available"
    )
  }

  func waitForAuthorizationCode(timeout: TimeInterval = 180) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      self.continuation = continuation
      lock.unlock()

      listener.newConnectionHandler = { [weak self] connection in
        self?.handle(connection)
      }

      listener.stateUpdateHandler = { [weak self] state in
        if case .failed(let error) = state {
          self?.finish(.failure(CodexAuthTokenStoreError.callbackServerFailed(error.localizedDescription)))
        }
      }

      listener.start(queue: queue)
      queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
        self?.finish(.failure(CodexAuthTokenStoreError.callbackTimedOut))
      }
    }
  }

  func cancel() {
    finish(.failure(CodexAuthTokenStoreError.callbackRejected("cancelled")))
  }

  private func handle(_ connection: NWConnection) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
      guard let self else {
        connection.cancel()
        return
      }

      if let error {
        self.respond(
          to: connection,
          title: "Codex Quota Login Failed",
          message: error.localizedDescription
        )
        self.finish(.failure(CodexAuthTokenStoreError.callbackServerFailed(error.localizedDescription)))
        return
      }

      guard let data,
            let request = String(data: data, encoding: .utf8),
            let path = Self.requestPath(from: request)
      else {
        self.respond(to: connection, title: "Codex Quota Login Failed", message: "Invalid callback request.")
        self.finish(.failure(CodexAuthTokenStoreError.callbackServerFailed("invalid callback request")))
        return
      }

      do {
        let code = try self.authorizationCode(from: path)
        self.respond(
          to: connection,
          title: "Codex Quota Login Complete",
          message: "You can return to Codex Quota Glass."
        )
        self.finish(.success(code))
      } catch {
        self.respond(to: connection, title: "Codex Quota Login Failed", message: error.localizedDescription)
        self.finish(.failure(error))
      }
    }
  }

  private func authorizationCode(from path: String) throws -> String {
    guard let url = URL(string: "http://localhost:\(port)\(path)"),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else {
      throw CodexAuthTokenStoreError.callbackServerFailed("invalid callback URL")
    }

    let query = Dictionary(
      uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
        item.value.map { (item.name, $0) }
      }
    )

    if let error = query["error"] {
      throw CodexAuthTokenStoreError.callbackRejected(error)
    }

    guard query["state"] == state else {
      throw CodexAuthTokenStoreError.callbackStateMismatch
    }

    guard let code = query["code"], !code.isEmpty else {
      throw CodexAuthTokenStoreError.callbackServerFailed("callback did not include an authorization code")
    }

    return code
  }

  private func respond(to connection: NWConnection, title: String, message: String) {
    let body = """
    <!doctype html><html><head><meta charset="utf-8"><title>\(title)</title></head>\
    <body style="font: -apple-system-body; padding: 32px;">\
    <h1>\(title)</h1><p>\(message)</p></body></html>
    """
    let response = """
    HTTP/1.1 200 OK\r
    Content-Type: text/html; charset=utf-8\r
    Content-Length: \(Data(body.utf8).count)\r
    Connection: close\r
    \r
    \(body)
    """

    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
      connection.cancel()
    })
  }

  private func finish(_ result: Result<String, Error>) {
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }

    finished = true
    let continuation = continuation
    self.continuation = nil
    lock.unlock()

    listener.cancel()

    switch result {
    case .success(let code):
      continuation?.resume(returning: code)
    case .failure(let error):
      continuation?.resume(throwing: error)
    }
  }

  private static func requestPath(from request: String) -> String? {
    guard let line = request.components(separatedBy: "\r\n").first else {
      return nil
    }

    let parts = line.split(separator: " ")
    guard parts.count >= 2 else {
      return nil
    }

    return String(parts[1])
  }
}

private extension Data {
  init?(base64URLEncoded string: String) {
    var base64 = string
      .replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")

    let padding = base64.count % 4
    if padding > 0 {
      base64 += String(repeating: "=", count: 4 - padding)
    }

    self.init(base64Encoded: base64)
  }

  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}

private extension JSONDecoder.DateDecodingStrategy {
  static let codexISO8601 = custom { decoder in
    let container = try decoder.singleValueContainer()
    let string = try container.decode(String.self)

    if let date = DateFormatters.date(from: string, fractionalSeconds: true) {
      return date
    }

    if let date = DateFormatters.date(from: string, fractionalSeconds: false) {
      return date
    }

    throw DecodingError.dataCorruptedError(
      in: container,
      debugDescription: "Invalid ISO8601 date: \(string)"
    )
  }
}

private enum DateFormatters {
  static func date(from string: String, fractionalSeconds: Bool) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = fractionalSeconds
      ? [.withInternetDateTime, .withFractionalSeconds]
      : [.withInternetDateTime]
    return formatter.date(from: string)
  }
}
