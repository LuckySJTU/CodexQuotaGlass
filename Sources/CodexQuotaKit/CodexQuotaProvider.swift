import Foundation

public struct CodexQuotaProvider: Sendable {
  public var apiClient: CodexUsageAPIClient
  public var cache: QuotaSnapshotCache

  public init(
    apiClient: CodexUsageAPIClient = CodexUsageAPIClient(),
    cache: QuotaSnapshotCache = QuotaSnapshotCache()
  ) {
    self.apiClient = apiClient
    self.cache = cache
  }

  public func loadCachedOrPlaceholder() -> QuotaSnapshot {
    cache.load() ?? .placeholder()
  }

  @discardableResult
  public func refresh() async throws -> QuotaSnapshot {
    let snapshot = try await apiClient.fetchSnapshot()
    try cache.save(snapshot)
    return snapshot
  }
}
