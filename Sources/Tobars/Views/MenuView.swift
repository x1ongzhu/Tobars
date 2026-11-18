import AppKit
import SwiftUI
import TobarsCore

/// 把菜单内容与 `AppState` 解耦，方便离屏渲染与预览。
struct MenuContentData {
    var accounts: [Account] = []
    var usage: [UUID: ProviderUsage] = [:]
    var errors: [UUID: String] = [:]
    var lastRefresh: Date?
    var isRefreshing: Bool = false

    var visibleAccounts: [Account] {
        accounts.filter { usage[$0.id] != nil || errors[$0.id] != nil }
    }
}

struct MenuContentView: View {
    let data: MenuContentData
    var onRefresh: () -> Void = {}
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if data.accounts.isEmpty {
                emptyState(
                    symbol: "person.badge.plus",
                    title: "还没有添加账号",
                    message: "同一家服务可以添加多个账号。"
                )
            } else if data.visibleAccounts.isEmpty {
                if data.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    emptyState(
                        symbol: "key.horizontal",
                        title: "账号还没有凭据",
                        message: nil
                    )
                }
            } else {
                cards
            }
            Divider()
            footer
        }
        .frame(width: 384)
    }

    private func emptyState(symbol: String, title: String, message: String?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button("打开设置", action: onSettings)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private var cards: some View {
        VStack(spacing: 10) {
            ForEach(data.visibleAccounts) { account in
                if let usage = data.usage[account.id] {
                    ProviderCard(account: account, usage: usage)
                } else if let error = data.errors[account.id] {
                    ProviderErrorCard(account: account, message: error)
                }
            }
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            TobarsMark(colored: true)
                .frame(width: 15, height: 15)
            Text("Tobars")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if let last = data.lastRefresh {
                Text(UsageFormatting.relative(last))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .rotationEffect(.degrees(data.isRefreshing ? 360 : 0))
                    .animation(
                        data.isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .default,
                        value: data.isRefreshing
                    )
            }
            .buttonStyle(.plain)
            .disabled(data.isRefreshing)
            .help("刷新")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("设置…", action: onSettings)
                .buttonStyle(.plain)
                .font(.system(size: 12))
            Spacer()
            Button("退出", action: onQuit)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct ProviderCard: View {
    let account: Account
    let usage: ProviderUsage

    private var accent: Color {
        switch usage.peakPercent ?? 0 {
        case 0..<60: return .green
        case 60..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderLogo(provider: account.provider)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.displayName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let peak = usage.peakPercent {
                    Text(UsageFormatting.percent(peak))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                }
            }

            ForEach(usage.windows) { window in
                UsageWindowRow(window: window, accent: accent)
            }

            if let note = usage.note {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            if let balance = usage.balance {
                Text(balance)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    /// 固定为「服务商 · 套餐 · 账号」，不随账号名是否等于服务商名而变化。
    private var subtitle: String {
        [account.provider.displayName, usage.planName, usage.accountLabel]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct UsageWindowRow: View {
    let window: UsageWindow
    let accent: Color

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(window.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if let detail = window.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(UsageFormatting.percent(window.usedPercent))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(accent.opacity(0.85))
                        .frame(width: max(2, proxy.size.width * window.usedPercent / 100))
                }
            }
            .frame(height: 4)
            HStack(spacing: 4) {
                if let reset = window.resetsAt, let countdown = UsageFormatting.countdown(to: reset) {
                    Text("\(countdown) 后重置")
                } else {
                    Text(" ")
                }
                Spacer()
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }
}

private struct ProviderErrorCard: View {
    let account: Account
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ProviderLogo(provider: account.provider)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Text(account.provider.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.red.opacity(0.06))
        )
    }
}

struct MenuView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        MenuContentView(
            data: MenuContentData(
                accounts: state.accounts,
                usage: state.usage,
                errors: state.errors,
                lastRefresh: state.lastRefresh,
                isRefreshing: state.isRefreshing
            ),
            onRefresh: { Task { await state.refresh() } },
            onSettings: { SettingsWindowController.shared.show(state: state) },
            onQuit: { NSApp.terminate(nil) }
        )
        .task { await state.refresh() }
    }
}
