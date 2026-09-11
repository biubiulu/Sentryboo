import Foundation

struct ZabbixAccount: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var baseURL: String
    var minimumSeverity: Int
    var allowInsecureTLS: Bool

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        minimumSeverity: AlertSeverity = .warning,
        allowInsecureTLS: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.minimumSeverity = minimumSeverity.rawValue
        self.allowInsecureTLS = allowInsecureTLS
    }

    var severity: AlertSeverity {
        AlertSeverity(rawValue: minimumSeverity) ?? .warning
    }

    var displayURL: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed) else { return trimmed }
        let host = components.host ?? trimmed
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty || path == "api_jsonrpc.php" {
            return host
        }
        return "\(host)/\(path)"
    }
}
