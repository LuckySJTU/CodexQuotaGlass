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

  private let provider: CodexQuotaProvider
  private var autoRefreshTask: Task<Void, Never>?

  init(provider: CodexQuotaProvider = CodexQuotaProvider()) {
    self.provider = provider
    let hasAuth = provider.apiClient.tokenStore.hasPrivateAuth
    isLoggedIn = hasAuth
    let initialSnapshot = hasAuth ? provider.loadCachedOrPlaceholder() : .placeholder()
    snapshot = initialSnapshot
    statusText = hasAuth && !initialSnapshot.isPlaceholder
      ? "更新于 \(QuotaFormatting.capturedTime(initialSnapshot.capturedAt))"
      : "去登录"

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

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 60_000_000_000)
        await self?.refresh()
      }
    }
  }

  func refresh() async {
    guard !isRefreshing else {
      return
    }

    guard provider.apiClient.tokenStore.hasPrivateAuth else {
      showLoggedOutState()
      return
    }

    isRefreshing = true
    defer {
      isRefreshing = false
    }

    do {
      let provider = provider
      let refreshed = try await Task.detached(priority: .utility) {
        try await provider.refresh()
      }.value
      isLoggedIn = true
      snapshot = refreshed
      statusText = "更新于 \(QuotaFormatting.capturedTime(refreshed.capturedAt))"
      reloadSystemSurfaces()
    } catch {
      let cached = provider.loadCachedOrPlaceholder()
      snapshot = cached
      statusText = cached.isPlaceholder ? "需要登录或重新授权" : "使用缓存：\(QuotaFormatting.capturedTime(cached.capturedAt))"
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
      await refresh()
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
      await refresh()
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
    QuotaFormatting.resetClock(snapshot.fiveHour.resetsAt)
  }

  var weeklyResetText: String {
    QuotaFormatting.resetDays(snapshot.weekly.resetsAt)
  }

  var authStorageText: String {
    provider.apiClient.tokenStore.authFileURL.path
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
    statusText = "去登录"
    saveLoggedOutSnapshot(placeholder)
    reloadSystemSurfaces()
  }

  private func saveLoggedOutSnapshot(_ placeholder: QuotaSnapshot) {
    let provider = provider
    Task.detached(priority: .utility) {
      try? provider.cache.save(placeholder)
    }
  }
}
