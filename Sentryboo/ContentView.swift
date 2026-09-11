import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var session: AlertSession

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
                HStack(spacing: 6) {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                    if showsRefreshPulse {
                        BreathingDot()
                    }
                }
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
        case .idle where session.accounts.isEmpty:
            emptyState(
                title: "尚未配置",
                detail: "打开设置，添加至少一台 Zabbix（名称、URL、API Token）。"
            )
        case .idle:
            // 已有账号但尚未出结果（静默首刷）：不误显示「尚未配置」。
            ProgressView("同步中…")
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding()
        case .error(let message):
            emptyState(title: "同步失败", detail: message)
        case .ok where session.problems.isEmpty:
            emptyState(title: "暂无未恢复问题", detail: "当前过滤条件下一切正常。")
        case .partial(_, _) where session.problems.isEmpty:
            emptyState(title: "暂无未恢复问题", detail: statusText)
        case .syncing where session.problems.isEmpty:
            // 静默刷新后几乎不会进入；保留兜底，避免首刷空白。
            ProgressView("同步中…")
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding()
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
            .disabled(session.isRefreshInFlight)
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

    /// 弹层在 NSPopover 内，openWindow 环境不可靠；交给 AppDelegate / Settings 场景打开。
    private func openSettingsWindow() {
        NotificationCenter.default.post(name: .sentrybooOpenSettings, object: nil)
        DispatchQueue.main.async {
            AppDelegate.shared?.openSettingsWindow()
        }
    }

    private var showsRefreshPulse: Bool {
        if isIdleUnconfigured { return false }
        return session.isRefreshingPulse
    }

    private var isIdleUnconfigured: Bool {
        if case .idle = session.status { return session.accounts.isEmpty }
        return false
    }

    private var status: SourceStatus { session.status }

    private var statusText: String {
        switch session.status {
        case .idle where session.accounts.isEmpty:
            return "未配置数据源"
        case .idle:
            return "正在连接…"
        case .syncing:
            // 静默刷新后极少出现；若兜底触发，仍显示上一类连接文案感。
            return "已连接"
        case .ok(let count):
            return count == 0 ? "已连接 · 无问题" : "已连接 · \(count) 条问题"
        case .partial(let count, let failed):
            let names = failed.joined(separator: "、")
            let base = count == 0 ? "部分失败 · 无问题" : "部分失败 · \(count) 条问题"
            return "\(base)：\(names)"
        case .error:
            return "连接异常"
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .error:
            return .red
        case .partial:
            return .orange
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
            } else if case .partial = session.status {
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

private struct BreathingDot: View {
    @State private var glowing = false

    var body: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 7, height: 7)
            .opacity(glowing ? 1.0 : 0.35)
            .shadow(color: .green.opacity(glowing ? 0.7 : 0.15), radius: glowing ? 3 : 0)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: glowing)
            .onAppear { glowing = true }
            .accessibilityLabel("刚刚刷新")
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
                    Text(problem.sourceName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
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
