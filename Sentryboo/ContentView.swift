import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var session: AlertSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            middle
            Divider()
            footer
        }
        .frame(width: 360)
        .task {
            await session.refresh(reason: .appActivated)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sentryboo")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer()
            if let last = session.lastSyncedAt {
                Text(last, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var middle: some View {
        switch session.status {
        case .idle:
            emptyState(
                title: "尚未配置",
                detail: "打开设置，填写 Zabbix URL 与 API Token。"
            )
        case .error(let message):
            emptyState(title: "同步失败", detail: message)
        case .syncing where session.problems.isEmpty:
            ProgressView("同步中…")
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding()
        case .ok where session.problems.isEmpty:
            emptyState(title: "暂无未恢复问题", detail: "当前过滤条件下一切正常。")
        default:
            if session.problems.isEmpty {
                emptyState(title: "暂无未恢复问题", detail: "当前过滤条件下一切正常。")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(session.problems) { problem in
                            ProblemRow(problem: problem)
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("设置") { openSettingsWindow() }
            Button("刷新") {
                Task { await session.refresh(reason: .manual) }
            }
            .disabled(isSyncing)
            if session.canOpenZabbixFrontend {
                Button("打开 Web") {
                    session.openZabbixFrontend()
                }
            }
            Spacer()
            Button("退出") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
    }

    /// MenuBarExtra / LSUIElement 下直接 `openWindow` 常会静默失败，需先激活再打开并前置。
    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: Self.isSettingsWindow) {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        openWindow(id: "settings")
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: Self.isSettingsWindow)?.makeKeyAndOrderFront(nil)
        }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == "settings" {
            return true
        }
        return window.title == "Settings" || window.title == "设置"
    }

    private var isSyncing: Bool {
        if case .syncing = session.status { return true }
        return false
    }

    private var statusText: String {
        switch session.status {
        case .idle:
            return "未配置数据源"
        case .syncing:
            return "正在同步…"
        case .ok(let count):
            return count == 0 ? "已连接 · 无问题" : "已连接 · \(count) 条问题"
        case .error:
            return "连接异常"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .error:
            return .red
        default:
            return .secondary
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if case .idle = session.status {
                Button("打开设置") { openSettingsWindow() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
            } else if case .error = session.status {
                HStack(spacing: 8) {
                    Button("重试") {
                        Task { await session.refresh(reason: .manual) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button("打开设置") { openSettingsWindow() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .frame(minHeight: 120)
    }
}

private struct ProblemRow: View {
    let problem: AlertProblem

    var body: some View {
        Button {
            if let url = problem.url {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(problem.severity.displayName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(problem.severity.color.opacity(0.2))
                        .clipShape(Capsule())
                    if problem.acknowledged {
                        Text("已确认")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(problem.startedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(problem.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(problem.host)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(problem.url == nil)
        .help(problem.url == nil ? "无法拼出 Web 链接" : "在浏览器打开该问题")
    }
}
