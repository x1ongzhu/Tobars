import AppKit
import SwiftUI
import TobarsCore

struct TobarsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(state)
        } label: {
            MenuBarLabel(text: state.menuBarText)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 无 Dock 图标，只留菜单栏入口；打包成 .app 时 Info.plist 里还有 LSUIElement。
        NSApp.setActivationPolicy(.accessory)
        Task { await AppState.shared.start() }

        if CommandLine.arguments.contains("--show-settings") {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                SettingsWindowController.shared.show(state: AppState.shared)
            }
        }
    }
}
