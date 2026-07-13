import AppKit
import CodexQuotaKit
import SwiftUI

struct MenuBarPanel: View {
  @ObservedObject var model: QuotaViewModel
  @Environment(\.openWindow) private var openWindow
  @AppStorage(MenuBarLocalUsagePeriodPreference.storageKey)
  private var localUsagePeriodsRawValue = MenuBarLocalUsagePeriodPreference.defaultRawValue

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 10) {
        Image(systemName: "sparkles")
          .font(.title3)
          .symbolRenderingMode(.hierarchical)

        VStack(alignment: .leading, spacing: 2) {
          Text("Codex Quota")
            .font(.headline)
          Text(model.isLoggedIn ? model.statusText : "去登录")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        Spacer()

        Button {
          Task {
            await model.signInWithBrowser()
          }
        } label: {
          Image(systemName: model.isAuthenticating ? "clock.badge" : "safari")
        }
        .buttonStyle(.borderless)
        .disabled(model.isAuthenticating)
        .help("网页登录")

        Button {
          Task {
            await model.refresh(forceLocalUsage: true)
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .disabled(model.isRefreshing)
        .help("刷新")
      }

      if model.isLoggedIn {
        if model.snapshot.fiveHour.isAvailable {
          QuotaMetricCard(
            window: model.snapshot.fiveHour,
            resetText: model.fiveHourResetText,
            compact: true
          )

          QuotaMetricCard(
            window: model.snapshot.weekly,
            resetText: model.weeklyResetText,
            compact: true
          )
        } else {
          WeeklyOnlyQuotaCard(
            window: model.snapshot.weekly,
            resetText: model.weeklyResetText,
            compact: true
          )
        }
      } else {
        VStack(alignment: .leading, spacing: 10) {
          Text("去登录")
            .font(.title3.weight(.semibold))

          Text("登录后显示 Codex 剩余额度。")
            .font(.caption)
            .foregroundStyle(.secondary)

          Button {
            Task {
              await model.signInWithBrowser()
            }
          } label: {
            Label(model.isAuthenticating ? "登录中" : "去登录", systemImage: "safari")
          }
          .disabled(model.isAuthenticating)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .quotaGlass(cornerRadius: 16)
      }

      LocalUsageSummaryCard(
        summary: model.localUsageSummary,
        isRefreshing: model.isRefreshingLocalUsage,
        compact: true,
        displayedPeriods: MenuBarLocalUsagePeriodPreference.periods(from: localUsagePeriodsRawValue)
      )

      HStack {
        Button {
          openWindow(id: "dashboard")
          NSApp.activate(ignoringOtherApps: true)
        } label: {
          Label("详情", systemImage: "chart.pie")
        }

        Spacer()

        Button {
          NSApplication.shared.terminate(nil)
        } label: {
          Label("退出", systemImage: "power")
        }
      }
      .controlSize(.small)
    }
    .padding(16)
    .frame(width: 340)
  }
}
