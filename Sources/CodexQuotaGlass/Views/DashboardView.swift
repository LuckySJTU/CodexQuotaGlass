import AppKit
import CodexQuotaKit
import SwiftUI

struct DashboardView: View {
  @ObservedObject var model: QuotaViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      header

      if model.isLoggedIn {
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
        LoggedOutDetailCard(model: model)
      }

      VStack(alignment: .leading, spacing: 10) {
        DetailRow(
          title: "5 小时重置",
          value: model.fiveHourResetText,
          symbol: "clock"
        )
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
      }
      .padding(16)
      .quotaGlass(cornerRadius: 18)

      MenuBarStyleSettings()

      Spacer(minLength: 0)
    }
    .padding(22)
    .frame(minWidth: 560, minHeight: 460)
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

      Button {
        Task {
          await model.refresh()
        }
      } label: {
        Label(model.isRefreshing ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
      }
      .disabled(model.isRefreshing)
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

private struct LoggedOutDetailCard: View {
  @ObservedObject var model: QuotaViewModel

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

      HStack {
        Button {
          Task {
            await model.signInWithBrowser()
          }
        } label: {
          Label(model.isAuthenticating ? "登录中" : "去登录", systemImage: "safari")
        }
        .disabled(model.isAuthenticating)

        Button {
          Task {
            await model.importCodexAuth()
          }
        } label: {
          Label("从 Codex 快捷登录", systemImage: "tray.and.arrow.down")
        }

        Spacer()
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
