import Foundation

public struct CodexLocalUsageSummaryCache: Sendable {
  public static let fileName = "local-usage.json"

  public var fileURL: URL
  private var fallbackFileURLs: [URL]

  public init(fileURL: URL? = nil) {
    if let fileURL {
      self.fileURL = fileURL
      fallbackFileURLs = []
    } else {
      let fileURLs = QuotaSnapshotCache.defaultFileURLs(fileName: Self.fileName)
      self.fileURL = fileURLs[0]
      fallbackFileURLs = Array(fileURLs.dropFirst())
    }
  }

  public func load() -> CodexLocalUsageSummary? {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    return candidateFileURLs
      .compactMap { fileURL -> (summary: CodexLocalUsageSummary, modifiedAt: Date)? in
        guard
          let data = try? Data(contentsOf: fileURL),
          let summary = try? decoder.decode(CodexLocalUsageSummary.self, from: data)
        else {
          return nil
        }

        let modifiedAt = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date)
          ?? summary.generatedAt
        return (summary, modifiedAt)
      }
      .max { left, right in left.modifiedAt < right.modifiedAt }?
      .summary
  }

  public func save(_ summary: CodexLocalUsageSummary) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(summary)

    var firstError: Error?
    var didWrite = false

    for fileURL in candidateFileURLs {
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

  private var candidateFileURLs: [URL] {
    ([fileURL] + fallbackFileURLs).uniqued()
  }
}
