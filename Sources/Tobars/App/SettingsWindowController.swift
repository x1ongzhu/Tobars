import AppKit
import SwiftUI

/// 不用 SwiftUI 的 `Settings` scene：在 `.accessory` 的菜单栏 app 里，
/// `openSettings` 从 MenuBarExtra 弹窗触发时经常没有反应（窗口不出现/不置前）。
/// 这里手动管理一个 NSWindow，行为确定，也方便 `--show-settings` 调试。
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show(state: AppState) {
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsView().environmentObject(state)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Tobars 设置"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.window = window
        NSLog("Tobars: 已打开设置窗口")
    }
}
