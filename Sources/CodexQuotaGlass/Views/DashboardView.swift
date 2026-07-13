import AppKit
import CodexQuotaKit
import SwiftUI

struct DashboardView: View {
  @ObservedObject var model: QuotaViewModel

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header

        quotaSection

        LocalUsageSummaryCard(
          summary: model.localUsageSummary,
          isRefreshing: model.isRefreshingLocalUsage
        )

        detailStatusCard

        MenuBarStyleSettings()

        MenuBarLocalUsagePeriodSettings()

        DashboardActionsCard(model: model)

        AppUpdateCard(model: model)
      }
      .padding(22)
    }
    .frame(minWidth: 680, minHeight: 640)
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "gauge.with.dots.needle.67percent")
        .font(.title)
        .symbolRenderingMode(.hierarchical)

      VStack(alignment: .leading, spacing: 3) {
        Text("Codex Quota")
          .font(.title2.weight(.semibold))
        Text(model.isLoggedIn ? model.statusText : "去登录")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
  }

  @ViewBuilder
  private var quotaSection: some View {
    if model.isLoggedIn {
      if model.snapshot.fiveHour.isAvailable {
        HStack(spacing: 14) {
          QuotaMetricCard(
            window: model.snapshot.fiveHour,
            resetText: model.fiveHourResetText
          )

          QuotaMetricCard(
            window: model.snapshot.weekly,
            resetText: model.weeklyResetText
          )
        }
      } else {
        VStack(alignment: .leading, spacing: 12) {
          WeeklyOnlyQuotaCard(
            window: model.snapshot.weekly,
            resetText: model.weeklyResetText
          )

          CodexQuotaVersionNotice()
        }
      }
    } else {
      LoggedOutDetailCard()
    }
  }

  private var detailStatusCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      if model.snapshot.fiveHour.isAvailable {
        DetailRow(
          title: "5 小时重置",
          value: model.fiveHourResetText,
          symbol: "clock"
        )
      } else {
        DetailRow(
          title: "5 小时额度",
          value: "新版 Codex App 已取消",
          symbol: "clock.badge.xmark"
        )
      }

      DetailRow(
        title: "一周重置",
        value: model.weeklyResetText,
        symbol: "calendar"
      )
      DetailRow(
        title: "数据源",
        value: model.isLoggedIn ? "Codex 登录认证" : "去登录",
        symbol: "doc.text.magnifyingglass"
      )
      DetailRow(
        title: "认证文件",
        value: model.authStorageText,
        symbol: "lock.doc"
      )
      DetailRow(
        title: "本地用量",
        value: model.localUsageStatusText,
        symbol: "chart.bar.doc.horizontal"
      )
      DetailRow(
        title: "本地日志",
        value: model.localUsageSourceText,
        symbol: "folder"
      )
    }
    .padding(16)
    .quotaGlass(cornerRadius: 18)
  }
}

private struct AppUpdateCard: View {
  @ObservedObject var model: QuotaViewModel

  private var state: AppUpdateState {
    model.updateState
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: iconName)
          .frame(width: 18)
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 3) {
          Text("版本更新")
            .font(.callout)

          Text(state.statusText)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if state.isBusy {
          ProgressView()
            .controlSize(.small)
        }
      }

      HStack(spacing: 16) {
        UpdateInfoLabel(title: "当前", value: state.currentVersion)
        UpdateInfoLabel(title: "最新", value: state.latestVersion ?? "未知")
        UpdateInfoLabel(title: "上次检查", value: lastCheckedText)

        Spacer()

        Button {
          Task {
            await model.checkForUpdates(force: true, autoInstall: true)
          }
        } label: {
          Label("检查", systemImage: "arrow.clockwise")
        }
        .disabled(state.isBusy)

        if let downloadURL = state.downloadURL, state.canInstallUpdate {
          Button {
            Task {
              await model.installUpdate(from: downloadURL)
            }
          } label: {
            Label("立即更新", systemImage: "arrow.down.app")
          }
        }

        Button {
          NSWorkspace.shared.open(state.releasePageURL)
        } label: {
          Label("Release", systemImage: "safari")
        }
      }
      .controlSize(.small)
    }
    .padding(16)
    .quotaGlass(cornerRadius: 18)
  }

  private var lastCheckedText: String {
    guard let lastCheckedAt = state.lastCheckedAt else {
      return "从未"
    }

    return QuotaFormatting.capturedTime(lastCheckedAt)
  }

  private var iconName: String {
    switch state.phase {
    case .upToDate:
      "checkmark.circle"
    case .available, .downloading, .installing, .relaunching:
      "arrow.down.circle"
    case .failed:
      "exclamationmark.triangle"
    case .idle, .checking:
      "sparkle.magnifyingglass"
    }
  }
}

private struct UpdateInfoLabel: View {
  var title: String
  var value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)

      Text(value)
        .font(.caption.monospacedDigit())
        .lineLimit(1)
    }
  }
}

private struct MenuBarLocalUsagePeriodSettings: View {
  @AppStorage(MenuBarLocalUsagePeriodPreference.storageKey)
  private var periodsRawValue = MenuBarLocalUsagePeriodPreference.defaultRawValue

  private let columns = [
    GridItem(.adaptive(minimum: 92), spacing: 12, alignment: .leading),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: "menubar.arrow.up.rectangle")
          .frame(width: 18)
          .foregroundStyle(.secondary)

        VStack(alignment: .leading, spacing: 3) {
          Text("菜单栏 token 周期")
            .font(.callout)

          Text("只影响菜单栏弹窗，详情页始终展示全部周期。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
        ForEach(CodexUsagePeriod.allCases) { period in
          Toggle(period.title, isOn: binding(for: period))
            .toggleStyle(.checkbox)
            .font(.callout)
        }
      }
    }
    .padding(16)
    .quotaGlass(cornerRadius: 18)
  }

  private func binding(for period: CodexUsagePeriod) -> Binding<Bool> {
    Binding {
      MenuBarLocalUsagePeriodPreference.periods(from: periodsRawValue).contains(period)
    } set: { isSelected in
      var periods = MenuBarLocalUsagePeriodPreference.periods(from: periodsRawValue)

      if isSelected {
        if !periods.contains(period) {
          periods.append(period)
        }
      } else {
        periods.removeAll { $0 == period }
      }

      periodsRawValue = MenuBarLocalUsagePeriodPreference.rawValue(for: periods)
    }
  }
}

private struct MenuBarStyleSettings: View {
  @AppStorage(MenuBarDisplayStyle.storageKey) private var styleRawValue = MenuBarDisplayStyle.defaultStyle.rawValue

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "menubar.rectangle")
        .frame(width: 18)
        .foregroundStyle(.secondary)

      VStack(alignment: .leading, spacing: 3) {
        Text("菜单栏样式")
          .font(.callout)

        Text("切换后会立即更新菜单栏图标。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      Picker("菜单栏样式", selection: $styleRawValue) {
        ForEach(MenuBarDisplayStyle.allCases) { style in
          Text(style.title).tag(style.rawValue)
        }
      }
      .labelsHidden()
      .frame(width: 190)
    }
    .padding(16)
    .quotaGlass(cornerRadius: 18)
  }
}

private struct DashboardActionsCard: View {
  @ObservedObject var model: QuotaViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        LoginSyncIcon()

        VStack(alignment: .leading, spacing: 3) {
          Text("登录与同步")
            .font(.callout)

          Text("管理认证状态，并手动刷新额度和本地 token 用量。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()
      }

      HStack(spacing: 10) {
        Button {
          Task {
            await model.signInWithBrowser()
          }
        } label: {
          Label(model.isAuthenticating ? "登录中" : "网页登录", systemImage: "safari")
        }
        .disabled(model.isAuthenticating)

        Button {
          Task {
            await model.importCodexAuth()
          }
        } label: {
          Label("从 Codex 快捷登录", systemImage: "tray.and.arrow.down")
        }

        if model.isLoggedIn {
          Button(role: .destructive) {
            Task {
              await model.forgetAuth()
            }
          } label: {
            Label("退出登录", systemImage: "person.crop.circle.badge.xmark")
          }
        }

        Spacer()

        Button {
          Task {
            await model.refresh(forceLocalUsage: true)
          }
        } label: {
          Label(model.isRefreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
        }
        .disabled(model.isRefreshing)
      }
      .controlSize(.small)
    }
    .padding(16)
    .quotaGlass(cornerRadius: 18)
  }
}

private struct LoginSyncIcon: View {
  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      Image(systemName: "person.crop.circle")
        .font(.system(size: 16, weight: .regular))

      Image(systemName: "arrow.clockwise.circle.fill")
        .font(.system(size: 8, weight: .semibold))
        .background(Circle().fill(.background))
        .offset(x: 2, y: 2)
    }
    .symbolRenderingMode(.hierarchical)
    .foregroundStyle(.secondary)
    .frame(width: 18, height: 18)
  }
}

private struct LoggedOutDetailCard: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: "safari")
          .font(.title2)
          .symbolRenderingMode(.hierarchical)

        VStack(alignment: .leading, spacing: 3) {
          Text("去登录")
            .font(.title3.weight(.semibold))
          Text("登录后会在菜单栏和桌面小组件显示 Codex 剩余额度。")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .quotaGlass(cornerRadius: 20)
  }
}

private struct DetailRow: View {
  var title: String
  var value: String
  var symbol: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol)
        .frame(width: 18)
        .foregroundStyle(.secondary)

      Text(title)
        .foregroundStyle(.secondary)

      Spacer()

      Text(value)
        .monospacedDigit()
        .lineLimit(1)
    }
    .font(.callout)
  }
}
