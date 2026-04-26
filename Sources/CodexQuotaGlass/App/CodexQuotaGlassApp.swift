import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}

@main
struct CodexQuotaGlassApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var model = QuotaViewModel()

  var body: some Scene {
    MenuBarExtra {
      MenuBarPanel(model: model)
        .task {
          model.startAutoRefresh()
        }
    } label: {
      MenuBarStatusLabel(snapshot: model.snapshot)
        .task {
          model.startAutoRefresh()
        }
    }
    .menuBarExtraStyle(.window)

    Window("Codex Quota", id: "dashboard") {
      DashboardView(model: model)
        .task {
          model.startAutoRefresh()
        }
    }
  }
}
