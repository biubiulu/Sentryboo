import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var session: AlertSession
    @State private var baseURL: String = ""
    @State private var apiToken: String = ""
    @State private var minimumSeverity: AlertSeverity = .warning
    @State private var allowInsecureTLS = false
    @State private var testMessage: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Zabbix") {
                TextField("Base URL", text: $baseURL, prompt: Text("https://zabbix.example.com"))
                SecureField("API Token", text: $apiToken)
                Text("Token 仅保存在本机钥匙串，不会写入普通偏好设置。建议使用只读权限 Token。")
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
                        persist()
                        testMessage = "已保存本地配置。"
                    }
                    .disabled(baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(isTesting ? "测试中…" : "测试连接") {
                        Task { await runTest() }
                    }
                    .disabled(isTesting || baseURL.isEmpty || apiToken.isEmpty)
                }
                if let testMessage {
                    Text(testMessage)
                        .font(.caption)
                        .foregroundStyle(testMessageColor)
                }
            }

            Section("同步") {
                LabeledContent("轮询间隔", value: "15 秒（一期固定）")
                Text("一期通过轮询 problem.get 拉取未恢复问题；Zabbix 不会向客户端主动推送。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            let config = session.loadConfiguration()
            baseURL = config.baseURL
            apiToken = config.apiToken
            minimumSeverity = config.minimumSeverity
            allowInsecureTLS = config.allowInsecureTLS
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var testMessageColor: Color {
        guard let testMessage else { return .secondary }
        if testMessage.contains("成功") || testMessage.contains("已保存") {
            return .secondary
        }
        return .red
    }

    private func persist() {
        session.saveConfiguration(
            baseURL: baseURL,
            apiToken: apiToken,
            minimumSeverity: minimumSeverity,
            allowInsecureTLS: allowInsecureTLS
        )
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        persist()
        do {
            let version = try await session.validateConnection()
            testMessage = "连接成功：Zabbix API \(version)"
        } catch {
            testMessage = error.localizedDescription
        }
    }
}
