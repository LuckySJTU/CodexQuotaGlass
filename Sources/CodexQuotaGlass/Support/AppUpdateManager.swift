import AppKit
import CodexQuotaKit
import Foundation

enum AppUpdatePhase: Equatable {
  case idle
  case checking
  case upToDate
  case available
  case downloading
  case installing
  case relaunching
  case failed(String)
}

struct AppUpdateState: Equatable {
  var currentVersion: String
  var latestVersion: String?
  var lastCheckedAt: Date?
  var releasePageURL: URL
  var downloadURL: URL?
  var phase: AppUpdatePhase

  var isBusy: Bool {
    switch phase {
    case .checking, .downloading, .installing, .relaunching:
      true
    case .idle, .upToDate, .available, .failed:
      false
    }
  }

  var updateAvailable: Bool {
    phase == .available
  }

  var canInstallUpdate: Bool {
    guard downloadURL != nil, let latestVersion, !isBusy else {
      return false
    }

    return AppVersion(latestVersion) > AppVersion(currentVersion)
  }

  var statusText: String {
    switch phase {
    case .idle:
      if let lastCheckedAt {
        return "上次检查 \(QuotaFormatting.capturedTime(lastCheckedAt))"
      }
      return "尚未检查"
    case .checking:
      return "正在检查更新"
    case .upToDate:
      return "已是最新版本"
    case .available:
      return "发现新版本 \(latestVersion ?? "")，将自动更新"
    case .downloading:
      return "正在下载新版本"
    case .installing:
      return "正在安装新版本"
    case .relaunching:
      return "正在重启应用"
    case .failed(let message):
      return message
    }
  }

  static func initial(
    currentVersion: String,
    releasePageURL: URL,
    lastCheckedAt: Date?
  ) -> AppUpdateState {
    AppUpdateState(
      currentVersion: currentVersion,
      latestVersion: nil,
      lastCheckedAt: lastCheckedAt,
      releasePageURL: releasePageURL,
      downloadURL: nil,
      phase: .idle
    )
  }
}

struct AppUpdateCheckResult: Equatable {
  var latestVersion: String
  var releasePageURL: URL
  var downloadURL: URL?
  var isUpdateAvailable: Bool
}

final class AppUpdateManager: @unchecked Sendable {
  private let releasesAPIURL = URL(string: "https://api.github.com/repos/LuckySJTU/CodexQuotaGlass/releases/latest")!
  private let releasePageURL = URL(string: "https://github.com/LuckySJTU/CodexQuotaGlass/releases")!
  private let latestReleaseURL = URL(string: "https://github.com/LuckySJTU/CodexQuotaGlass/releases/latest")!
  private let defaults: UserDefaults
  private let fileManager: FileManager
  private let lastCheckKey = "appUpdateLastCheckAt"

  init(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
    self.defaults = defaults
    self.fileManager = fileManager
  }

  var currentVersionText: String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

    if let build, !build.isEmpty {
      return "\(version) (\(build))"
    }

    return version
  }

  var currentComparableVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
  }

  var lastCheckedAt: Date? {
    defaults.object(forKey: lastCheckKey) as? Date
  }

  func initialState() -> AppUpdateState {
    .initial(
      currentVersion: currentVersionText,
      releasePageURL: releasePageURL,
      lastCheckedAt: lastCheckedAt
    )
  }

  func shouldCheck(now: Date = Date()) -> Bool {
    guard let lastCheckedAt else {
      return true
    }

    return now.timeIntervalSince(lastCheckedAt) >= 24 * 60 * 60
  }

  func checkLatestRelease(now: Date = Date()) async throws -> AppUpdateCheckResult {
    defer {
      defaults.set(now, forKey: lastCheckKey)
    }

    do {
      return try await checkLatestReleaseFromAPI()
    } catch {
      return try await checkLatestReleaseFromWeb()
    }
  }

  private func checkLatestReleaseFromAPI() async throws -> AppUpdateCheckResult {
    let (data, response) = try await URLSession.shared.data(for: githubRequest(url: releasesAPIURL, accept: "application/vnd.github+json"))
    guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
      throw AppUpdateError.badResponse
    }

    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
    let latestVersion = release.tagName
    let latestPageURL = URL(string: release.htmlURL) ?? releasePageURL
    let downloadURL = release.assets
      .filter { $0.name.localizedCaseInsensitiveContains(".dmg") }
      .compactMap { URL(string: $0.browserDownloadURL) }
      .first

    return AppUpdateCheckResult(
      latestVersion: latestVersion,
      releasePageURL: latestPageURL,
      downloadURL: downloadURL,
      isUpdateAvailable: AppVersion(latestVersion) > AppVersion(currentComparableVersion)
    )
  }

  private func checkLatestReleaseFromWeb() async throws -> AppUpdateCheckResult {
    let (data, response) = try await URLSession.shared.data(for: githubRequest(url: latestReleaseURL, accept: "text/html"))
    guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
      throw AppUpdateError.badResponse
    }

    let html = String(decoding: data, as: UTF8.self)
    guard let latestVersion = tagName(from: response.url) ?? tagName(fromHTML: html) else {
      throw AppUpdateError.badResponse
    }

    let latestPageURL = URL(string: "https://github.com/LuckySJTU/CodexQuotaGlass/releases/tag/\(latestVersion)") ?? releasePageURL
    let downloadURL = try await downloadURLFromExpandedAssets(tagName: latestVersion)

    return AppUpdateCheckResult(
      latestVersion: latestVersion,
      releasePageURL: latestPageURL,
      downloadURL: downloadURL,
      isUpdateAvailable: AppVersion(latestVersion) > AppVersion(currentComparableVersion)
    )
  }

  func downloadAndInstall(from downloadURL: URL) async throws {
    let cacheDirectory = try updateCacheDirectory()
    let destinationURL = cacheDirectory.appendingPathComponent(downloadURL.lastPathComponent.isEmpty ? "CodexQuotaGlass.dmg" : downloadURL.lastPathComponent)

    let (temporaryURL, response) = try await URLSession.shared.download(from: downloadURL)
    guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
      throw AppUpdateError.badResponse
    }

    try? fileManager.removeItem(at: destinationURL)
    try fileManager.moveItem(at: temporaryURL, to: destinationURL)

    try launchInstaller(for: destinationURL)
  }

  private func updateCacheDirectory() throws -> URL {
    let baseDirectory = try fileManager.url(
      for: .cachesDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = baseDirectory.appendingPathComponent("CodexQuotaGlass/Updates", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func githubRequest(url: URL, accept: String) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("CodexQuotaGlass/\(currentComparableVersion)", forHTTPHeaderField: "User-Agent")
    request.setValue(accept, forHTTPHeaderField: "Accept")
    return request
  }

  private func downloadURLFromExpandedAssets(tagName: String) async throws -> URL? {
    guard let assetsURL = URL(string: "https://github.com/LuckySJTU/CodexQuotaGlass/releases/expanded_assets/\(tagName)") else {
      return nil
    }

    let (data, response) = try await URLSession.shared.data(for: githubRequest(url: assetsURL, accept: "text/html"))
    guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
      throw AppUpdateError.badResponse
    }

    let html = String(decoding: data, as: UTF8.self)
    guard let href = firstMatch(in: html, pattern: #"href="([^"]+\.dmg[^"]*)""#) else {
      return nil
    }

    let decodedHref = href.replacingOccurrences(of: "&amp;", with: "&")
    if decodedHref.hasPrefix("http") {
      return URL(string: decodedHref)
    }

    return URL(string: "https://github.com\(decodedHref)")
  }

  private func tagName(from url: URL?) -> String? {
    guard let components = url?.pathComponents, let tagIndex = components.firstIndex(of: "tag") else {
      return nil
    }

    let valueIndex = components.index(after: tagIndex)
    guard valueIndex < components.endIndex else {
      return nil
    }

    return components[valueIndex]
  }

  private func tagName(fromHTML html: String) -> String? {
    firstMatch(in: html, pattern: #"/releases/tag/([^"?#<]+)"#)
  }

  private func firstMatch(in text: String, pattern: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return nil
    }

    let range = NSRange(text.startIndex ..< text.endIndex, in: text)
    guard
      let match = regex.firstMatch(in: text, range: range),
      match.numberOfRanges > 1,
      let captureRange = Range(match.range(at: 1), in: text)
    else {
      return nil
    }

    return String(text[captureRange])
  }

  private func launchInstaller(for dmgURL: URL) throws {
    let scriptURL = fileManager.temporaryDirectory
      .appendingPathComponent("CodexQuotaGlassInstall-\(UUID().uuidString).zsh")
    let appURL = Bundle.main.bundleURL
    let script = installerScript

    try script.write(to: scriptURL, atomically: true, encoding: .utf8)
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/zsh")
    process.arguments = [scriptURL.path, dmgURL.path, appURL.path]
    try process.run()
  }

  private var installerScript: String {
    """
    #!/bin/zsh
    set -euo pipefail

    DMG_PATH="$1"
    CURRENT_APP="$2"
    APP_NAME="CodexQuotaGlass.app"
    MOUNT_DIR="$(/usr/bin/mktemp -d /tmp/CodexQuotaGlassUpdate.XXXXXX)"

    cleanup() {
      /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
      /bin/rm -rf "$MOUNT_DIR"
      /bin/rm -f "$0"
    }
    trap cleanup EXIT

    /usr/bin/hdiutil attach "$DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet -readonly
    SOURCE_APP="$(/usr/bin/find "$MOUNT_DIR" -maxdepth 3 -name "$APP_NAME" -type d | /usr/bin/head -n 1)"

    if [[ -z "$SOURCE_APP" ]]; then
      exit 2
    fi

    for _ in {1..80}; do
      if ! /usr/bin/pgrep -x "CodexQuotaGlass" >/dev/null 2>&1; then
        break
      fi
      /bin/sleep 0.25
    done

    TEMP_APP="${CURRENT_APP}.updating"
    /bin/rm -rf "$TEMP_APP"
    /usr/bin/ditto "$SOURCE_APP" "$TEMP_APP"
    /usr/bin/codesign --verify --deep --strict "$TEMP_APP"
    /bin/rm -rf "$CURRENT_APP"
    /bin/mv "$TEMP_APP" "$CURRENT_APP"
    /usr/bin/xattr -dr com.apple.quarantine "$CURRENT_APP" >/dev/null 2>&1 || true
    /bin/rm -f "$DMG_PATH"
    /usr/bin/open -n "$CURRENT_APP"
    """
  }
}

private struct GitHubRelease: Decodable {
  var tagName: String
  var htmlURL: String
  var assets: [GitHubReleaseAsset]

  enum CodingKeys: String, CodingKey {
    case tagName = "tag_name"
    case htmlURL = "html_url"
    case assets
  }
}

private struct GitHubReleaseAsset: Decodable {
  var name: String
  var browserDownloadURL: String

  enum CodingKeys: String, CodingKey {
    case name
    case browserDownloadURL = "browser_download_url"
  }
}

private struct AppVersion: Comparable {
  var components: [Int]

  init(_ rawValue: String) {
    let trimmed = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    let groups = trimmed.split { !$0.isNumber }.compactMap { Int($0) }
    components = Array(groups.prefix(3))
  }

  static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
    let count = max(lhs.components.count, rhs.components.count, 3)

    for index in 0 ..< count {
      let left = index < lhs.components.count ? lhs.components[index] : 0
      let right = index < rhs.components.count ? rhs.components[index] : 0

      if left != right {
        return left < right
      }
    }

    return false
  }
}

private enum AppUpdateError: LocalizedError {
  case badResponse
  case missingDMG

  var errorDescription: String? {
    switch self {
    case .badResponse:
      "更新服务器响应异常"
    case .missingDMG:
      "最新版本没有可安装的 DMG"
    }
  }
}
