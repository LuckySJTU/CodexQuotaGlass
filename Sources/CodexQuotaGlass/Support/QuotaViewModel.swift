import AppKit
import Combine
import CodexQuotaKit
import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class QuotaViewModel: ObservableObject {
  @Published private(set) var snapshot: QuotaSnapshot
  @Published private(set) var isRefreshing = false
  @Published private(set) var isAuthenticating = false
  @Published private(set) var isLoggedIn: Bool
  @Published private(set) var statusText: String
  @Published private(set) var localUsageSummary: CodexLocalUsageSummary
  @Published private(set) var isRefreshingLocalUsage = false
  @Published private(set) var updateState: AppUpdateState
  @Published private(set) var accountInfo: CodexAccountInfo?
  @Published private(set) var accountInfoStatusText: String

  private let provider: CodexQuotaProvider
  private let accountClient: CodexAccountAPIClient
  private let localUsageProvider: CodexLocalUsageProvider
  private let appUpdateManager: AppUpdateManager
  private let minimumLocalUsageRefreshInterval: TimeInterval = 5 * 60
  private var autoRefreshTask: Task<Void, Never>?
  private var lastLocalUsageRefreshAt: Date?

  init(
    provider: CodexQuotaProvider = CodexQuotaProvider(),
    accountClient: CodexAccountAPIClient? = nil,
    localUsageProvider: CodexLocalUsageProvider = CodexLocalUsageProvider(),
    appUpdateManager: AppUpdateManager = AppUpdateManager()
  ) {
    self.provider = provider
    self.accountClient = accountClient ?? CodexAccountAPIClient(tokenStore: provider.apiClient.tokenStore)
    self.localUsageProvider = localUsageProvider
    self.appUpdateManager = appUpdateManager
    let hasAuth = provider.apiClient.tokenStore.hasPrivateAuth
    isLoggedIn = hasAuth
    let initialSnapshot = hasAuth ? provider.loadCachedOrPlaceholder() : .placeholder()
    snapshot = initialSnapshot
    let initialAccountInfo = initialSnapshot.planType.map {
      CodexAccountInfo.fallback(
        planType: $0,
        capturedAt: initialSnapshot.capturedAt,
        source: initialSnapshot.source
      )
    }
    accountInfo = initialAccountInfo
    localUsageSummary = CodexLocalUsageSummaryCache().load() ?? .empty()
    updateState = appUpdateManager.initialState()
    if hasAuth {
      statusText = initialSnapshot.isPlaceholder
        ? "正在刷新"
        : "更新于 \(QuotaFormatting.capturedTime(initialSnapshot.capturedAt))"
      accountInfoStatusText = initialAccountInfo == nil ? "正在获取订阅信息" : "来自 quota 缓存"
    } else {
      statusText = "去登录"
      accountInfoStatusText = "去登录"
    }

    if !hasAuth {
      saveLoggedOutSnapshot(initialSnapshot)
    }

    Task { [weak self] in
      self?.startAutoRefresh()
    }
  }

  deinit {
    autoRefreshTask?.cancel()
  }

  func startAutoRefresh() {
    guard autoRefreshTask == nil else {
      return
    }

    autoRefreshTask = Task { [weak self] in
      await self?.refresh()
      await self?.checkForUpdatesIfNeeded()

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 60_000_000_000)
        await self?.refresh()
        await self?.checkForUpdatesIfNeeded()
      }
    }
  }

  func refresh(forceLocalUsage: Bool = false) async {
    guard !isRefreshing else {
      return
    }

    isRefreshing = true
    defer {
      isRefreshing = false
    }

    Task { [weak self] in
      await self?.refreshLocalUsage(force: forceLocalUsage)
    }

    guard provider.apiClient.tokenStore.hasPrivateAuth else {
      showLoggedOutState()
      return
    }

    do {
      let provider = provider
      let refreshed = try await Task.detached(priority: .utility) {
        try await provider.refresh()
      }.value
      isLoggedIn = true
      snapshot = refreshed
      statusText = "更新于 \(QuotaFormatting.capturedTime(refreshed.capturedAt))"
      await refreshAccountInfo(fallbackSnapshot: refreshed)
      reloadSystemSurfaces()
    } catch {
      let cached = provider.loadCachedOrPlaceholder()
      snapshot = cached
      applyFallbackAccountInfo(from: cached, reason: error.localizedDescription)
      statusText = cached.isPlaceholder
        ? "刷新失败：\(error.localizedDescription)"
        : "使用缓存：\(QuotaFormatting.capturedTime(cached.capturedAt))"
    }
  }

  func refreshLocalUsage(force: Bool = false) async {
    guard !isRefreshingLocalUsage else {
      return
    }

    let now = Date()
    if
      !force,
      localUsageSummary.parsedEventCount > 0,
      let lastLocalUsageRefreshAt,
      now.timeIntervalSince(lastLocalUsageRefreshAt) < minimumLocalUsageRefreshInterval
    {
      return
    }

    isRefreshingLocalUsage = true
    defer {
      isRefreshingLocalUsage = false
    }

    let localUsageProvider = localUsageProvider
    let summary = await Task.detached(priority: .utility) {
      await localUsageProvider.loadSummary()
    }.value
    localUsageSummary = summary
    lastLocalUsageRefreshAt = summary.generatedAt
    try? await Task.detached(priority: .utility) {
      try CodexLocalUsageSummaryCache().save(summary)
    }.value
    reloadSystemSurfaces()
  }

  func refreshAccountInfo(fallbackSnapshot: QuotaSnapshot? = nil) async {
    guard isLoggedIn else {
      accountInfo = nil
      accountInfoStatusText = "去登录"
      return
    }

    let accountClient = accountClient

    do {
      let info = try await Task.detached(priority: .utility) {
        try await accountClient.fetchAccountInfo()
      }.value
      accountInfo = info
      accountInfoStatusText = "更新于 \(QuotaFormatting.capturedTime(info.capturedAt))"
      applyAccountInfoToSnapshot(info)
    } catch {
      if let fallbackSnapshot {
        applyFallbackAccountInfo(from: fallbackSnapshot, reason: error.localizedDescription)
      } else {
        accountInfoStatusText = "订阅信息获取失败：\(error.localizedDescription)"
      }
    }
  }

  func checkForUpdatesIfNeeded() async {
    guard appUpdateManager.shouldCheck() else {
      return
    }

    await checkForUpdates(force: false, autoInstall: true)
  }

  func checkForUpdates(force: Bool = true, autoInstall: Bool = true) async {
    guard !updateState.isBusy else {
      return
    }

    if !force && !appUpdateManager.shouldCheck() {
      return
    }

    updateState.phase = .checking
    let checkedAt = Date()

    do {
      let result = try await appUpdateManager.checkLatestRelease(now: checkedAt)
      updateState.latestVersion = result.latestVersion
      updateState.releasePageURL = result.releasePageURL
      updateState.downloadURL = result.downloadURL
      updateState.lastCheckedAt = checkedAt
      updateState.phase = result.isUpdateAvailable ? .available : .upToDate

      guard result.isUpdateAvailable, autoInstall else {
        return
      }

      guard let downloadURL = result.downloadURL else {
        updateState.phase = .failed("发现新版本，但 release 里没有 DMG")
        return
      }

      await installUpdate(from: downloadURL)
    } catch {
      updateState.lastCheckedAt = checkedAt
      updateState.phase = .failed("检查更新失败：\(error.localizedDescription)")
    }
  }

  func installUpdate(from downloadURL: URL) async {
    guard updateState.canInstallUpdate else {
      return
    }

    updateState.phase = .downloading

    do {
      try await appUpdateManager.downloadAndInstall(from: downloadURL)
      updateState.phase = .relaunching
      NSApplication.shared.terminate(nil)
    } catch {
      updateState.phase = .failed("自动更新失败：\(error.localizedDescription)")
    }
  }

  func signInWithBrowser() async {
    guard !isAuthenticating else {
      return
    }

    isAuthenticating = true
    statusText = "正在打开网页登录"
    defer {
      isAuthenticating = false
    }

    do {
      let authenticator = CodexWebOAuthAuthenticator(tokenStore: provider.apiClient.tokenStore)
      try await authenticator.authenticate { url in
        NSWorkspace.shared.open(url)
      }

      statusText = "登录成功，正在刷新"
      isLoggedIn = true
      await refresh(forceLocalUsage: true)
    } catch {
      statusText = "登录失败：\(error.localizedDescription)"
    }
  }

  func importCodexAuth() async {
    do {
      let tokenStore = provider.apiClient.tokenStore
      let didImport = try await Task.detached(priority: .utility) {
        try tokenStore.importFromCodexIfNeeded()
      }.value

      statusText = didImport ? "已从 Codex 快捷登录，正在刷新" : "已使用私有登录"
      isLoggedIn = true
      await refresh(forceLocalUsage: true)
    } catch {
      statusText = "导入失败：\(error.localizedDescription)"
    }
  }

  func forgetAuth() async {
    do {
      let tokenStore = provider.apiClient.tokenStore
      try await Task.detached(priority: .utility) {
        try tokenStore.removePrivateAuth()
      }.value
      showLoggedOutState()
    } catch {
      statusText = "移除失败：\(error.localizedDescription)"
    }
  }

  var fiveHourResetText: String {
    guard snapshot.fiveHour.isAvailable else {
      return "未提供"
    }

    return QuotaFormatting.resetClock(snapshot.fiveHour.resetsAt)
  }

  var weeklyResetText: String {
    guard snapshot.weekly.isAvailable else {
      return "未提供"
    }

    return QuotaFormatting.resetDays(snapshot.weekly.resetsAt)
  }

  var authStorageText: String {
    provider.apiClient.tokenStore.authFileURL.path
  }

  var localUsageStatusText: String {
    guard localUsageSummary.parsedEventCount > 0 else {
      return "未找到本地用量"
    }

    return "本地用量更新于 \(QuotaFormatting.capturedTime(localUsageSummary.generatedAt))"
  }

  var localUsageSourceText: String {
    localUsageSummary.codexDirectory
  }

  var subscriptionPlanText: String {
    guard isLoggedIn else {
      return "去登录"
    }

    if let accountInfo {
      return accountInfo.displayPlanName
    }

    return snapshot.subscriptionDisplayName
  }

  var subscriptionDetailText: String {
    guard isLoggedIn else {
      return "去登录"
    }

    guard let accountInfo else {
      return accountInfoStatusText
    }

    return accountInfo.rawSummaryText
  }

  private func reloadSystemSurfaces() {
    #if canImport(WidgetKit)
    WidgetCenter.shared.reloadAllTimelines()
    #endif
  }

  private func showLoggedOutState() {
    let placeholder = QuotaSnapshot.placeholder()
    isLoggedIn = false
    snapshot = placeholder
    accountInfo = nil
    accountInfoStatusText = "去登录"
    statusText = "去登录"
    saveLoggedOutSnapshot(placeholder)
    reloadSystemSurfaces()
  }

  private func applyFallbackAccountInfo(from snapshot: QuotaSnapshot, reason: String) {
    if let planType = snapshot.planType, !snapshot.isPlaceholder {
      accountInfo = CodexAccountInfo.fallback(
        planType: planType,
        capturedAt: snapshot.capturedAt,
        source: snapshot.source
      )
      accountInfoStatusText = "账户接口失败，使用 quota 字段：\(reason)"
    } else {
      accountInfo = nil
      accountInfoStatusText = "订阅信息获取失败：\(reason)"
    }
  }

  private func applyAccountInfoToSnapshot(_ info: CodexAccountInfo) {
    var updated = snapshot
    updated.planType = info.planType ?? updated.planType
    updated.subscriptionPlan = info.subscriptionPlan
    snapshot = updated

    let provider = provider
    Task.detached(priority: .utility) {
      try? provider.cache.save(updated)
    }

    reloadSystemSurfaces()
  }

  private func saveLoggedOutSnapshot(_ placeholder: QuotaSnapshot) {
    let provider = provider
    Task.detached(priority: .utility) {
      try? provider.cache.save(placeholder)
    }
  }

}
