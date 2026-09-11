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

    @Published private(set) var status: SourceStatus = .idle
    @Published private(set) var problems: [AlertProblem] = []
    @Published private(set) var lastSyncedAt: Date?

    private let keychain = KeychainStore()
    private let defaults = UserDefaults.standard
    private var source: ZabbixSource?
    private var loopTask: Task<Void, Never>?

    private let baseURLKey = "zabbix.baseURL"
    private let minimumSeverityKey = "zabbix.minimumSeverity"
    private let allowInsecureTLSKey = "zabbix.allowInsecureTLS"

    init() {
        rebuildSource()
        startLoop()
    }

    deinit {
        loopTask?.cancel()
    }

    struct Configuration {
        var baseURL: String
        var apiToken: String
        var minimumSeverity: AlertSeverity
        var allowInsecureTLS: Bool
    }

    func loadConfiguration() -> Configuration {
        let url = defaults.string(forKey: baseURLKey) ?? ""
        let token = (try? keychain.readToken()) ?? ""
        let severityRaw = defaults.object(forKey: minimumSeverityKey) as? Int ?? AlertSeverity.warning.rawValue
        let severity = AlertSeverity(rawValue: severityRaw) ?? .warning
        let allowInsecure = defaults.bool(forKey: allowInsecureTLSKey)
        return Configuration(
            baseURL: url,
            apiToken: token,
            minimumSeverity: severity,
            allowInsecureTLS: allowInsecure
        )
    }

    func saveConfiguration(
        baseURL: String,
        apiToken: String,
        minimumSeverity: AlertSeverity,
        allowInsecureTLS: Bool
    ) {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmedURL, forKey: baseURLKey)
        defaults.set(minimumSeverity.rawValue, forKey: minimumSeverityKey)
        defaults.set(allowInsecureTLS, forKey: allowInsecureTLSKey)
        do {
            if apiToken.isEmpty {
                try keychain.deleteToken()
            } else {
                try keychain.saveToken(apiToken)
            }
        } catch {
            status = .error(error.localizedDescription)
            return
        }
        rebuildSource()
        Task { await refresh(reason: .manual) }
    }

    func validateConnection() async throws -> String {
        guard let source else {
            throw SourceError.notConfigured
        }
        return try await source.validate()
    }

    func openZabbixFrontend() {
        let config = loadConfiguration()
        guard let url = ZabbixSource.frontendBaseURL(from: config.baseURL) else { return }
        NSWorkspace.shared.open(url)
    }

    var canOpenZabbixFrontend: Bool {
        let config = loadConfiguration()
        return !config.baseURL.isEmpty && ZabbixSource.frontendBaseURL(from: config.baseURL) != nil
    }

    func refresh(reason: RefreshReason) async {
        guard let source else {
            status = .idle
            problems = []
            return
        }
        if case .syncing = status, reason == .timer {
            return
        }
        status = .syncing
        do {
            let items = try await source.fetchOpenProblems()
            problems = items
            lastSyncedAt = Date()
            status = .ok(count: items.count)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func rebuildSource() {
        let config = loadConfiguration()
        guard !config.baseURL.isEmpty, !config.apiToken.isEmpty else {
            source = nil
            status = .idle
            return
        }
        source = ZabbixSource(
            baseURL: config.baseURL,
            apiToken: config.apiToken,
            minimumSeverity: config.minimumSeverity,
            allowInsecureTLS: config.allowInsecureTLS
        )
    }

    private func startLoop() {
        loopTask?.cancel()
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { return }
                await self.refresh(reason: .timer)
            }
        }
    }
}
