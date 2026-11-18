import AppKit
import SwiftUI
import TobarsCore

/// 菜单栏弹窗不方便截图，提供离屏渲染：
///   .build/debug/Tobars --render-snapshot /tmp/tobars
enum SnapshotRenderer {
    @MainActor
    static func run(outputDirectory: String) {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let accounts = DemoData.accounts
        let usage = DemoData.usage()
        let data = MenuContentData(
            accounts: accounts,
            usage: usage,
            lastRefresh: Date().addingTimeInterval(-45),
            isRefreshing: false
        )

        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "menu-light.png" : "menu-dark.png"
            render(
                MenuContentView(data: data)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme),
                width: 384,
                to: directory.appendingPathComponent(name)
            )
        }

        let state = AppState()
        let previewCredentials = Dictionary(uniqueKeysWithValues: accounts.map { account in
            (account.id, ProviderCredential(apiKey: "preview-key-\(account.id.uuidString.prefix(4))"))
        })
        state.applyPreviewData(accounts: accounts, usage: usage, credentials: previewCredentials)
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "settings-light.png" : "settings-dark.png"
            captureInWindow(
                SettingsView()
                    .environmentObject(state)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme),
                width: 560,
                to: directory.appendingPathComponent(name)
            )
        }
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "menubar-light.png" : "menubar-dark.png"
            render(
                MenuBarLabel(text: "98%")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, scheme),
                width: 90,
                to: directory.appendingPathComponent(name)
            )
        }

        let emptyState = AppState()
        captureInWindow(
            SettingsView()
                .environmentObject(emptyState)
                .background(Color(nsColor: .windowBackgroundColor)),
            width: 560,
            to: directory.appendingPathComponent("settings-empty.png")
        )

        print("snapshot: \(directory.path)")
        exit(0)
    }

    @MainActor
    private static func render<V: View>(_ view: V, width: CGFloat, to url: URL) {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            fputs("snapshot: 渲染失败 \(url.lastPathComponent)\n", stderr)
            return
        }
        write(png, to: url)
    }

    /// 设置页含 AppKit 控件（TextField / Picker），ImageRenderer 会把它们画成黄色占位；
    /// 放进真实 NSWindow 再用 cacheDisplay 才能得到可用截图。
    @MainActor
    private static func captureInWindow<V: View>(_ view: V, width: CGFloat, to url: URL) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 100)
        hosting.layoutSubtreeIfNeeded()
        let height = max(100, hosting.fittingSize.height)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            fputs("snapshot: 无法创建 settings 位图\n", stderr)
            window.orderOut(nil)
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            write(png, to: url)
        }
        window.orderOut(nil)
    }

    private static func write(_ data: Data, to url: URL) {
        do {
            try data.write(to: url)
        } catch {
            fputs("snapshot: 写入失败 \(error.localizedDescription)\n", stderr)
        }
    }
}
