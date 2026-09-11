import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var session: AlertSession
    @ObservedObject private var debugLog = DebugLog.shared
    @State private var path: [SettingsRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    if session.accounts.isEmpty {
                        Text("还没有 Zabbix 账号。点下方「添加账号」开始配置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.accounts) { account in
                            NavigationLink(value: SettingsRoute.edit(account.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name)
                                        .font(.body.weight(.medium))
                                    Text(account.displayURL)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete(perform: deleteAccounts)
                    }
                } header: {
                    Text("Zabbix 账号")
                } footer: {
                    Text("每台可独立设置名称、URL、Token、最低严重级别与自签证书。菜单栏会合并所有账号的问题并标出来源。")
                }

                Section {
                    Button("添加账号") {
                        path.append(.create)
                    }
                }

                Section {
                    HStack {
                        Text("轮询间隔（秒）")
                        Spacer()
                        TextField("", value: pollIntervalBinding, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                            .textFieldStyle(.roundedBorder)
                    }
                    Text("默认 15 秒，可填 5–300。对齐 Zabbix「监视 → 问题 → 最近问题」；改完后下一轮轮询即生效。一台失败时仍显示其他台结果。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("同步")
                }

                Section("调试") {
                    Toggle("DEBUG 模式", isOn: $debugLog.isEnabled)
                    Text("开启后记录 API 请求/响应（Token 已脱敏），可在下方查看或复制。也可在 Console.app 搜索「Sentryboo」。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if debugLog.isEnabled {
                        ScrollView {
                            Text(debugLog.joinedText.isEmpty ? "暂无日志。点「测试连接」或「刷新」后会出现。" : debugLog.joinedText)
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 120, maxHeight: 220)
                        HStack {
                            Button("清空日志") { debugLog.clear() }
                            Button("复制日志") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(debugLog.joinedText, forType: .string)
                            }
                            .disabled(debugLog.entries.isEmpty)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .create:
                    AccountEditorView(mode: .create) {
                        path.removeLast()
                    }
                case .edit(let id):
                    if let account = session.account(id: id) {
                        AccountEditorView(mode: .edit(account)) {
                            path.removeLast()
                        }
                    } else {
                        Text("账号不存在或已删除。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 560)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var pollIntervalBinding: Binding<Int> {
        Binding(
            get: { session.pollIntervalSeconds },
            set: { session.setPollIntervalSeconds($0) }
        )
    }

    private func deleteAccounts(at offsets: IndexSet) {
        for index in offsets {
            let id = session.accounts[index].id
            session.deleteAccount(id: id)
        }
    }
}

private enum SettingsRoute: Hashable {
    case create
    case edit(UUID)
}

private struct AccountEditorView: View {
    enum Mode {
        case create
        case edit(ZabbixAccount)
    }

    @EnvironmentObject private var session: AlertSession
    let mode: Mode
    let onFinish: () -> Void

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiToken: String = ""
    @State private var minimumSeverity: AlertSeverity = .warning
    @State private var allowInsecureTLS = false
    @State private var testMessage: String?
    @State private var isTesting = false
    @State private var showDeleteConfirm = false

    private var editingID: UUID? {
        if case .edit(let account) = mode { return account.id }
        return nil
    }

    var body: some View {
        Form {
            Section("账号") {
                TextField("名称", text: $name, prompt: Text("生产 / 测试"))
                TextField("Base URL", text: $baseURL, prompt: Text("https://zabbix.example.com"))
                SecureField("API Token", text: $apiToken)
                Text("名称会出现在菜单栏问题列表的来源标签上。Token 加密保存在本机 Application Support。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("过滤与安全") {
                Picker("最低严重级别", selection: $minimumSeverity) {
                    ForEach(AlertSeverity.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level)
                    }
                }
                Toggle("信任此主机证书（自签 / 内网）", isOn: $allowInsecureTLS)
                Text("默认校验证书。仅在内网自签 HTTPS 时开启；开启后对该连接放宽 TLS 校验。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("保存") {
                        save()
                    }
                    .disabled(!canSave)

                    Button(isTesting ? "测试中…" : "测试连接") {
                        Task { await runTest() }
                    }
                    .disabled(isTesting || !canTest)
                }
                if let testMessage {
                    Text(testMessage)
                        .font(.caption)
                        .foregroundStyle(testMessageColor)
                }
            }

            if editingID != nil {
                Section {
                    Button("删除此账号", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(editingID == nil ? "添加账号" : "编辑账号")
        .onAppear(perform: load)
        .confirmationDialog("确定删除该 Zabbix 账号？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let editingID {
                    session.deleteAccount(id: editingID)
                    onFinish()
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTest: Bool {
        canSave && !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var testMessageColor: Color {
        guard let testMessage else { return .secondary }
        if testMessage.contains("成功") || testMessage.contains("已保存") {
            return .secondary
        }
        return .red
    }

    private func load() {
        switch mode {
        case .create:
            name = ""
            baseURL = ""
            apiToken = ""
            minimumSeverity = .warning
            allowInsecureTLS = false
        case .edit(let account):
            name = account.name
            baseURL = account.baseURL
            apiToken = session.loadToken(for: account.id)
            minimumSeverity = account.severity
            allowInsecureTLS = account.allowInsecureTLS
        }
    }

    private func save() {
        guard let savedID = session.upsertAccount(
            id: editingID,
            name: name,
            baseURL: baseURL,
            apiToken: apiToken,
            minimumSeverity: minimumSeverity,
            allowInsecureTLS: allowInsecureTLS
        ) else {
            testMessage = "保存失败，请检查名称与 URL。"
            return
        }
        _ = savedID
        testMessage = "已保存本地配置。"
        onFinish()
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        do {
            let version = try await session.validateConnection(
                name: name,
                baseURL: baseURL,
                apiToken: apiToken,
                minimumSeverity: minimumSeverity,
                allowInsecureTLS: allowInsecureTLS
            )
            testMessage = "连接成功：Zabbix API \(version)"
        } catch {
            testMessage = error.localizedDescription
        }
    }
}
