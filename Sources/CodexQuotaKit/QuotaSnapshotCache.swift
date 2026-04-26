import Foundation

public struct QuotaSnapshotCache: Sendable {
  public static let appGroupInfoKey = "CodexQuotaAppGroupIdentifier"
  public static let legacyAppGroupIdentifier = "group.com.local.CodexQuotaGlass"
  public static let appSupportDirectoryName = "CodexQuotaGlass"
  public static let fileName = "quota.json"

  public var fileURL: URL

  public init(fileURL: URL = QuotaSnapshotCache.defaultFileURL()) {
    self.fileURL = fileURL
  }

  public static func defaultFileURL(
    fileManager: FileManager = .default,
    bundle: Bundle = .main
  ) -> URL {
    for appGroupIdentifier in appGroupIdentifiers(bundle: bundle) {
      if let containerURL = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      ) {
        return containerURL.appendingPathComponent(fileName, isDirectory: false)
      }
    }

    let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    return supportURL
      .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
      .appendingPathComponent(fileName, isDirectory: false)
  }

  public static func appGroupIdentifiers(bundle: Bundle = .main) -> [String] {
    var identifiers: [String] = []

    if let value = bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String {
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty && !trimmed.contains("$(") {
        identifiers.append(trimmed)
      }
    }

    identifiers.append(legacyAppGroupIdentifier)
    return identifiers.uniqued()
  }

  public func load() -> QuotaSnapshot? {
    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? decoder.decode(QuotaSnapshot.self, from: data)
  }

  public func save(_ snapshot: QuotaSnapshot) throws {
    let directoryURL = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshot)
    try data.write(to: fileURL, options: [.atomic])
  }
}

private extension Array where Element == String {
  func uniqued() -> [String] {
    var seen = Set<String>()
    return filter { seen.insert($0).inserted }
  }
}
