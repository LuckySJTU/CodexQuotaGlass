import Foundation

public struct QuotaSnapshotCache: Sendable {
  public static let appGroupInfoKey = "CodexQuotaAppGroupIdentifier"
  public static let legacyAppGroupIdentifier = "group.com.local.CodexQuotaGlass"
  public static let appSupportDirectoryName = "CodexQuotaGlass"
  public static let fileName = "quota.json"

  public var fileURL: URL
  private var fallbackFileURLs: [URL]

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
      fallbackFileURLs = []
    } else {
      let fileURLs = QuotaSnapshotCache.defaultFileURLs()
      self.fileURL = fileURLs[0]
      fallbackFileURLs = Array(fileURLs.dropFirst())
    }
  }

  public static func defaultFileURL(
    fileManager: FileManager = .default,
    bundle: Bundle = .main
  ) -> URL {
    defaultFileURLs(fileManager: fileManager, bundle: bundle)[0]
  }

  public static func defaultFileURLs(
    fileName: String = QuotaSnapshotCache.fileName,
    fileManager: FileManager = .default,
    bundle: Bundle = .main
  ) -> [URL] {
    var fileURLs: [URL] = []

    for appGroupIdentifier in appGroupIdentifiers(bundle: bundle) {
      if let containerURL = fileManager.containerURL(
        forSecurityApplicationGroupIdentifier: appGroupIdentifier
      ) {
        fileURLs.append(containerURL.appendingPathComponent(fileName, isDirectory: false))
      }
    }

    let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
    fileURLs.append(
      supportURL
      .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
      .appendingPathComponent(fileName, isDirectory: false)
    )

    return fileURLs.uniqued()
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
    let candidates = readableSnapshots()
    return candidates.max { left, right in
      left.modifiedAt < right.modifiedAt
    }?.snapshot
  }

  public func save(_ snapshot: QuotaSnapshot) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(snapshot)

    try write(data, to: candidateFileURLs)
  }

  private var candidateFileURLs: [URL] {
    ([fileURL] + fallbackFileURLs).uniqued()
  }

  private func readableSnapshots() -> [(snapshot: QuotaSnapshot, modifiedAt: Date)] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    return candidateFileURLs.compactMap { fileURL in
      guard
        let data = try? Data(contentsOf: fileURL),
        let snapshot = try? decoder.decode(QuotaSnapshot.self, from: data)
      else {
        return nil
      }

      let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date)
        ?? snapshot.capturedAt
      return (snapshot, modifiedAt)
    }
  }

  private func write(_ data: Data, to fileURLs: [URL]) throws {
    var firstError: Error?
    var didWrite = false

    for fileURL in fileURLs {
      do {
        try FileManager.default.createDirectory(
          at: fileURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: [.atomic])
        didWrite = true
      } catch {
        firstError = firstError ?? error
      }
    }

    if !didWrite, let firstError {
      throw firstError
    }
  }
}

private extension Array where Element == String {
  func uniqued() -> [String] {
    var seen = Set<String>()
    return filter { seen.insert($0).inserted }
  }
}

extension Array where Element == URL {
  func uniqued() -> [URL] {
    var seen = Set<String>()
    return filter { seen.insert($0.path).inserted }
  }
}
