import SwiftUI
import TobarsCore

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                if state.accounts.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        accountCards
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 560, height: 640)
    }

    private var accountCards: some View {
        VStack(spacing: 10) {
            ForEach(state.accounts) { account in
                AccountSettingsCard(accountID: account.id)
                    .environmentObject(state)
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                TobarsMark(colored: true)
                    .frame(width: 18, height: 18)
                Text("设置")
                    .font(.system(size: 18, weight: .semibold))
            }
            Spacer()
            if !state.accounts.isEmpty {
                AddAccountMenu()
                    .environmentObject(state)
                Button {
                    Task { await state.refresh() }
                } label: {
                    Label("全部刷新", systemImage: "arrow.clockwise")
                }
                .controlSize(.small)
                .disabled(state.isRefreshing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text("还没有添加账号")
                .font(.system(size: 13, weight: .medium))
            Text("同一家服务可以添加多个账号。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            AddAccountMenu(prominent: true)
                .environmentObject(state)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("\(state.accounts.count) 个账号")
            if let last = state.lastRefresh {
                Text("· 上次刷新 \(UsageFormatting.relative(last))")
            }
            Spacer()
            Text("v0.1")
                .foregroundStyle(.tertiary)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

private struct AddAccountMenu: View {
    var prominent = false
    @EnvironmentObject private var state: AppState

    var body: some View {
        Menu {
            ForEach(ProviderID.allCases) { provider in
                Button(provider.displayName) {
                    state.addAccount(provider: provider)
                }
            }
        } label: {
            Label(prominent ? "添加第一个账号" : "添加账号", systemImage: "plus")
        }
        .menuStyle(.borderedButton)
        .fixedSize()
        .controlSize(.small)
    }
}

private struct AccountSettingsCard: View {
    let accountID: UUID
    @EnvironmentObject private var state: AppState

    private enum Mode {
        case summary
        case editing
    }

    private enum AuthMode: String, CaseIterable {
        case apiKey = "Control Key"
        case cookie = "浏览器 Cookie"

        var fieldTitle: String {
            switch self {
            case .apiKey: return "API key"
            case .cookie: return "Cookie 请求头"
            }
        }
    }

    private struct StatusMessage {
        let text: String
        let isError: Bool
    }

    @State private var mode: Mode = .editing
    @State private var authMode: AuthMode = .apiKey
    @State private var apiKey = ""
    @State private var cookie = ""
    @State private var workspaceID = ""
    @State private var labelDraft = ""
    @State private var renaming = false
    @State private var status: StatusMessage?
    @State private var busy = false
    @State private var showRemoveConfirm = false
    @State private var localKeyAvailable = false
    @FocusState private var fieldFocused: Bool
    @FocusState private var labelFocused: Bool

    private var account: Account? {
        state.accounts.first { $0.id == accountID }
    }

    var body: some View {
        if let account {
            VStack(alignment: .leading, spacing: 8) {
                cardHeader(account)
                switch mode {
                case .summary:
                    summaryBody(account)
                case .editing:
                    editingBody(account)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035))
            )
            .onAppear { synchronize(account) }
            .confirmationDialog(
                "移除账号「\(account.displayName)」？",
                isPresented: $showRemoveConfirm
            ) {
                Button("移除账号", role: .destructive) {
                    state.removeAccount(accountID)
                }
                Button("取消", role: .cancel) {}
            }
        }
    }

    // MARK: - 头部

    private func cardHeader(_ account: Account) -> some View {
        HStack(spacing: 8) {
            ProviderLogo(provider: account.provider, size: 20)
            if renaming {
                TextField("账号名称", text: $labelDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 180)
                    .focused($labelFocused)
                    .onSubmit { finishRenaming(account) }
                    .onChange(of: labelFocused) { _, focused in
                        if !focused { finishRenaming(account) }
                    }
            } else {
                Text(account.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Button {
                    labelDraft = account.displayName
                    renaming = true
                    DispatchQueue.main.async { labelFocused = true }
                } label: {
                    Text("重命名")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }

            Text(account.provider.displayName)
                .font(.system(size: 9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .foregroundStyle(.secondary)

            statusChip

            Spacer()
            Link(destination: account.provider.consoleURL) {
                HStack(spacing: 2) {
                    Text("控制台")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 9))
            }
        }
    }

    private var statusChip: some View {
        let (text, color): (String, Color) = {
            if state.errors[accountID] != nil { return ("出错", .red) }
            if state.usage[accountID] != nil { return ("已连接", .green) }
            if isConfigured { return ("已配置", .secondary) }
            return ("未配置", .secondary)
        }()
        return Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }

    // MARK: - 已配置：只显示摘要，不把密钥填回输入框

    @ViewBuilder
    private func summaryBody(_ account: Account) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "key.fill")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(maskedSecret(account))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            if let workspace = state.credential(for: account)?.workspaceID, !workspace.isEmpty {
                Text("· 工作区 \(workspace)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }

        if let usage = state.usage[accountID] {
            Text(usageLine(usage))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if let error = state.errors[accountID] {
            Text(error)
                .font(.system(size: 10))
                .foregroundStyle(.red)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }

        if let status {
            statusLine(status)
        }

        HStack(spacing: 8) {
            Button(busy ? "测试中…" : "测试连接", action: { testCurrent(account) })
                .disabled(busy)
            Button("更换凭据", action: { startEditing(account) })
                .disabled(busy)
            Spacer()
            Button("移除账号", role: .destructive) { showRemoveConfirm = true }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .disabled(busy)
        }
        .controlSize(.small)
    }

    // MARK: - 未配置 / 更换：只有一个主操作「保存并连接」

    @ViewBuilder
    private func editingBody(_ account: Account) -> some View {
        if account.provider == .openDesign {
            Picker("认证方式", selection: $authMode) {
                ForEach(AuthMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .font(.system(size: 10))
            Text(authMode == .cookie
                 ? "从控制台额度请求复制 Cookie 请求头。"
                 : "vela_ctrl_…，不是 sk-amr-… 推理密钥。")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }

        SecureField(fieldPlaceholder(account), text: secretBinding(account))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .focused($fieldFocused)

        if account.provider == .openDesign {
            TextField("Workspace ID（可留空自动发现）", text: $workspaceID)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
        }

        if let status {
            statusLine(status)
        }

        HStack(spacing: 8) {
            Button(busy ? "连接中…" : "保存并连接", action: { saveAndTest(account) })
                .buttonStyle(.borderedProminent)
                .disabled(busy)
            if isConfigured {
                Button("取消", action: { cancelEditing(account) })
                    .disabled(busy)
            }
            if localKeyAvailable {
                Button("从本机读取并连接", action: { importLocalAndConnect(account) })
                    .disabled(busy)
            }
            Spacer()
            Button(isConfigured ? "移除账号" : "取消添加", role: .destructive) {
                if isConfigured {
                    showRemoveConfirm = true
                } else {
                    state.removeAccount(accountID)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(busy)
        }
        .controlSize(.small)
    }

    // MARK: - 派生状态

    private func secretBinding(_ account: Account) -> Binding<String> {
        account.provider == .openDesign && authMode == .cookie ? $cookie : $apiKey
    }

    private func fieldPlaceholder(_ account: Account) -> String {
        if account.provider == .openDesign && authMode == .cookie {
            return "__Secure-better-auth.session_token=…"
        }
        return "粘贴 API key"
    }

    private var isConfigured: Bool {
        guard let account else { return false }
        return state.credential(for: account)?.isEmpty == false
    }

    private func maskedSecret(_ account: Account) -> String {
        guard let credential = state.credential(for: account) else { return "" }
        if credential.hasCookie { return "浏览器 Cookie（已保存）" }
        let key = credential.apiKey
        guard key.count > 4 else { return String(repeating: "•", count: max(key.count, 4)) }
        return "•••••••• \(key.suffix(4))"
    }

    private func usageLine(_ usage: ProviderUsage) -> String {
        var parts: [String] = []
        if let plan = usage.planName { parts.append(plan) }
        for window in usage.windows {
            parts.append("\(window.label) \(UsageFormatting.percent(window.usedPercent))")
        }
        return parts.joined(separator: " · ")
    }

    private func statusLine(_ status: StatusMessage) -> some View {
        Text(status.text)
            .font(.system(size: 10))
            .foregroundStyle(status.isError ? .red : .secondary)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 动作

    private func synchronize(_ account: Account) {
        labelDraft = account.displayName
        if let credential = state.credential(for: account), !credential.isEmpty {
            mode = .summary
            workspaceID = credential.workspaceID ?? ""
            authMode = credential.hasCookie ? .cookie : .apiKey
        } else {
            mode = .editing
        }
        localKeyAvailable = state.hasLocalKey(for: account.provider)
    }

    private func finishRenaming(_ account: Account) {
        state.rename(accountID, to: labelDraft)
        labelDraft = state.accounts.first { $0.id == accountID }?.displayName ?? account.displayName
        renaming = false
    }

    private func startEditing(_ account: Account) {
        apiKey = ""
        cookie = ""
        status = nil
        authMode = state.credential(for: account)?.hasCookie == true ? .cookie : .apiKey
        mode = .editing
        fieldFocused = true
    }

    private func cancelEditing(_ account: Account) {
        status = nil
        synchronize(account)
    }

    private func saveAndTest(_ account: Account) {
        let workspace = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let credential: ProviderCredential

        if account.provider == .openDesign && authMode == .cookie {
            let value = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                status = .init(text: "请粘贴 Cookie 请求头", isError: true)
                return
            }
            credential = ProviderCredential(apiKey: "", workspaceID: workspace.isEmpty ? nil : workspace, cookie: value)
        } else {
            let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else {
                status = .init(text: "请粘贴 API key", isError: true)
                return
            }
            credential = ProviderCredential(apiKey: value, workspaceID: workspace.isEmpty ? nil : workspace, cookie: nil)
        }

        busy = true
        status = .init(text: "正在保存并连接…", isError: false)

        Task {
            do {
                try await state.test(credential, for: account)
                try state.save(credential, for: account)
                busy = false
                mode = .summary
                let summary = state.usage[accountID].map(usageLine)
                status = .init(text: summary.map { "连接成功 · \($0)" } ?? "连接成功", isError: false)
            } catch {
                busy = false
                status = .init(text: "连接失败：\(error.localizedDescription)", isError: true)
            }
        }
    }

    private func testCurrent(_ account: Account) {
        busy = true
        status = .init(text: "正在测试…", isError: false)
        Task {
            do {
                try await state.refresh(accountID)
                busy = false
                let summary = state.usage[accountID].map(usageLine)
                status = .init(text: summary.map { "连接成功 · \($0)" } ?? "连接成功", isError: false)
            } catch {
                busy = false
                status = .init(text: error.localizedDescription, isError: true)
            }
        }
    }

    private func importLocalAndConnect(_ account: Account) {
        guard let key = state.importLocalKey(for: account.provider) else {
            status = .init(text: "本机没有找到可导入的登录信息", isError: true)
            return
        }
        authMode = .apiKey
        apiKey = key
        saveAndTest(account)
    }
}
