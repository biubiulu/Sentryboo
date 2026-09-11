import Foundation
import SwiftUI
import AppKit

@MainActor
final class AlertSession: ObservableObject {
    enum RefreshReason {
        case timer
        case manual
        case appActivated
    }

    static let defaultPollIntervalSeconds = 15
    static let pollIntervalRange = 5...300

    @Published private(set) var status: SourceStatus = .idle
    @Published private(set) var problems: [AlertProblem] = []
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var accounts: [ZabbixAccount] = []
    @Published private(set) var pollIntervalSeconds: Int = AlertSession.defaultPollIntervalSeconds
    @Published private(set) var isRefreshingPulse = false
    @Published private(set) var isRefreshInFlight = false

    private let tokenStore = TokenStore()
    private let defaults = UserDefaults.standard
    private var sources: [ZabbixSource] = []
    private var loopTask: Task<Void, Never>?
    private var pulseStopTask: Task<Void, Never>?

    private let accountsKey = "zabbix.accounts"
    private let pollIntervalKey = "zabbix.pollIntervalSeconds"
    private let legacyBaseURLKey = "zabbix.baseURL"
    private let legacyMinimumSeverityKey = "zabbix.minimumSeverity"
    private let legacyAllowInsecureTLSKey = "zabbix.allowInsecureTLS"

    init() {
        pollIntervalSeconds = loadPollInterval()
        migrateLegacyConfigurationIfNeeded()
        reloadAccounts()
        tokenStore.migrateFromKeychainIfNeeded(accountIDs: accounts.map(\.id))
        rebuildSources()
        startLoop()
    }

    deinit {
        loopTask?.cancel()
        pulseStopTask?.cancel()
    }

    func setPollIntervalSeconds(_ value: Int) {
        let clamped = Self.clampPollInterval(value)
        guard clamped != pollIntervalSeconds else {
            if defaults.object(forKey: pollIntervalKey) == nil {
                defaults.set(clamped, forKey: pollIntervalKey)
            }
            return
        }
        pollIntervalSeconds = clamped
        defaults.set(clamped, forKey: pollIntervalKey)
    }

    func account(id: UUID) -> ZabbixAccount? {
        accounts.first { $0.id == id }
    }

    func loadToken(for accountID: UUID) -> String {
        (try? tokenStore.readToken(accountID: accountID)) ?? ""
    }

    @discardableResult
    func upsertAccount(
        id: UUID?,
        name: String,
        baseURL: String,
        apiToken: String,
        minimumSeverity: AlertSeverity,
        allowInsecureTLS: Bool
    ) -> UUID? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedURL.isEmpty else {
            status = .error("名称与 Base URL 不能为空。")
            return nil
        }

        let accountID = id ?? UUID()
        var next = accounts
        let account = ZabbixAccount(
            id: accountID,
            name: trimmedName,
            baseURL: trimmedURL,
            minimumSeverity: minimumSeverity,
            allowInsecureTLS: allowInsecureTLS
        )
        if let index = next.firstIndex(where: { $0.id == accountID }) {
            next[index] = account
        } else {
            next.append(account)
        }

        do {
            if apiToken.isEmpty {
                try tokenStore.deleteToken(accountID: accountID)
            } else {
                try tokenStore.saveToken(apiToken, accountID: accountID)
            }
            persistAccounts(next)
            reloadAccounts()
            rebuildSources()
            Task { await refresh(reason: .manual) }
            return accountID
        } catch {
            status = .error(error.localizedDescription)
            return nil
        }
    }

    func deleteAccount(id: UUID) {
        do {
            try tokenStore.deleteToken(accountID: id)
            persistAccounts(accounts.filter { $0.id != id })
            reloadAccounts()
            rebuildSources()
            Task { await refresh(reason: .manual) }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func validateConnection(
        name: String,
        baseURL: String,
        apiToken: String,
        minimumSeverity: AlertSeverity,
        allowInsecureTLS: Bool
    ) async throws -> String {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, !trimmedToken.isEmpty else {
            throw SourceError.notConfigured
        }
        let source = ZabbixSource(
            accountID: UUID(),
            displayName: name.isEmpty ? "临时" : name,
            baseURL: trimmedURL,
            apiToken: trimmedToken,
            minimumSeverity: minimumSeverity,
            allowInsecureTLS: allowInsecureTLS
        )
        return try await source.validate()
    }

    func openZabbixFrontend() {
        guard let first = accounts.first,
              let url = ZabbixSource.frontendBaseURL(from: first.baseURL) else { return }
        NSWorkspace.shared.open(url)
    }

    var canOpenZabbixFrontend: Bool {
        accounts.count == 1
            && ZabbixSource.frontendBaseURL(from: accounts[0].baseURL) != nil
    }

    func refresh(reason: RefreshReason) async {
        guard !sources.isEmpty else {
            status = .idle
            problems = []
            isRefreshingPulse = false
            return
        }
        if isRefreshInFlight {
            if reason == .timer { return }
            // 手动/激活：跳过叠请求，避免并发打穿；下一次再刷。
            return
        }

        isRefreshInFlight = true
        beginRefreshPulse()
        defer { isRefreshInFlight = false }

        let snapshot = sources
        var merged: [AlertProblem] = []
        var failedNames: [String] = []

        await withTaskGroup(of: Result<(String, [AlertProblem]), AccountFetchError>.self) { group in
            for source in snapshot {
                group.addTask {
                    do {
                        let items = try await source.fetchOpenProblems()
                        return .success((source.displayName, items))
                    } catch {
                        return .failure(AccountFetchError(name: source.displayName, message: error.localizedDescription))
                    }
                }
            }

            for await result in group {
                switch result {
                case .success(let (_, items)):
                    merged.append(contentsOf: items)
                case .failure(let failure):
                    failedNames.append(failure.name)
                }
            }
        }

        merged.sort { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            return lhs.startedAt > rhs.startedAt
        }
        problems = merged
        lastSyncedAt = Date()

        if failedNames.isEmpty {
            status = .ok(count: merged.count)
        } else if merged.isEmpty && failedNames.count == snapshot.count {
            let names = failedNames.joined(separator: "、")
            status = .error("全部实例同步失败：\(names)")
        } else {
            status = .partial(okCount: merged.count, failedNames: failedNames.sorted())
        }

        schedulePulseStop(after: 1.5)
    }

    private struct AccountFetchError: Error {
        let name: String
        let message: String
    }

    private func reloadAccounts() {
        guard let data = defaults.data(forKey: accountsKey),
              let decoded = try? JSONDecoder().decode([ZabbixAccount].self, from: data) else {
            accounts = []
            return
        }
        accounts = decoded
    }

    private func persistAccounts(_ value: [ZabbixAccount]) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: accountsKey)
        }
    }

    private func rebuildSources() {
        sources = accounts.compactMap { account in
            let token = (try? tokenStore.readToken(accountID: account.id)) ?? ""
            let url = account.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, !token.isEmpty else { return nil }
            return ZabbixSource(
                accountID: account.id,
                displayName: account.name,
                baseURL: url,
                apiToken: token,
                minimumSeverity: account.severity,
                allowInsecureTLS: account.allowInsecureTLS
            )
        }
        if sources.isEmpty {
            status = .idle
            problems = []
            isRefreshingPulse = false
        }
    }

    private func loadPollInterval() -> Int {
        guard defaults.object(forKey: pollIntervalKey) != nil else {
            return Self.defaultPollIntervalSeconds
        }
        return Self.clampPollInterval(defaults.integer(forKey: pollIntervalKey))
    }

    private static func clampPollInterval(_ value: Int) -> Int {
        min(max(value, pollIntervalRange.lowerBound), pollIntervalRange.upperBound)
    }

    private func beginRefreshPulse() {
        pulseStopTask?.cancel()
        isRefreshingPulse = true
    }

    private func schedulePulseStop(after seconds: Double) {
        pulseStopTask?.cancel()
        pulseStopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.isRefreshingPulse = false
        }
    }

    private func migrateLegacyConfigurationIfNeeded() {
        if defaults.data(forKey: accountsKey) != nil {
            return
        }
        let legacyURL = defaults.string(forKey: legacyBaseURLKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 旧单账号元数据迁到 accounts；Token 由 TokenStore.migrateFromKeychainIfNeeded 统一处理。
        guard !legacyURL.isEmpty
                || defaults.object(forKey: legacyMinimumSeverityKey) != nil
                || defaults.object(forKey: legacyAllowInsecureTLSKey) != nil else {
            return
        }

        let severityRaw = defaults.object(forKey: legacyMinimumSeverityKey) as? Int
            ?? AlertSeverity.warning.rawValue
        let severity = AlertSeverity(rawValue: severityRaw) ?? .warning
        let allowInsecure = defaults.bool(forKey: legacyAllowInsecureTLSKey)
        let account = ZabbixAccount(
            name: "默认",
            baseURL: legacyURL,
            minimumSeverity: severity,
            allowInsecureTLS: allowInsecure
        )
        persistAccounts([account])
        defaults.removeObject(forKey: legacyBaseURLKey)
        defaults.removeObject(forKey: legacyMinimumSeverityKey)
        defaults.removeObject(forKey: legacyAllowInsecureTLSKey)
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = max(self?.pollIntervalSeconds ?? AlertSession.defaultPollIntervalSeconds, AlertSession.pollIntervalRange.lowerBound)
                try? await Task.sleep(for: .seconds(seconds))
                guard let self, !Task.isCancelled else { return }
                await self.refresh(reason: .timer)
            }
        }
    }
}
