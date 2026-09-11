import Foundation
import Combine

/// 运行时可开关的调试日志；默认关闭。Token 会脱敏后写入。
@MainActor
final class DebugLog: ObservableObject {
    static let shared = DebugLog()

    @Published private(set) var entries: [String] = []
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: defaultsKey)
            let stamp = Self.formatter.string(from: Date())
            let line = isEnabled ? "DEBUG 模式已开启" : "DEBUG 模式已关闭"
            // 开关本身始终记一条，方便确认状态变化。
            entries.append("[\(stamp)] \(line)")
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
            print("[Sentryboo] \(line)")
        }
    }

    private let defaultsKey = "app.debugLogging"
    private let maxEntries = 200

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: defaultsKey)
    }

    func clear() {
        entries.removeAll()
    }

    func append(_ message: String) {
        guard isEnabled else { return }
        let stamp = Self.formatter.string(from: Date())
        entries.append("[\(stamp)] \(message)")
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        // 同时打到系统日志，方便 Console.app / Xcode 查看。
        print("[Sentryboo] \(message)")
    }

    func request(method: String, url: String, body: String) {
        append("→ \(method) \(url)\n\(Self.redactSecrets(in: body))")
    }

    func response(method: String, statusCode: Int?, body: String) {
        let code = statusCode.map(String.init) ?? "?"
        append("← \(method) HTTP \(code)\n\(Self.redactSecrets(in: body))")
    }

    func error(_ message: String) {
        append("✖ \(message)")
    }

    var joinedText: String {
        entries.joined(separator: "\n\n")
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    /// 脱敏 Bearer / JSON auth / 长 token 字段。
    static func redactSecrets(in text: String) -> String {
        var result = text
        let replacements: [(String, String)] = [
            (#"("auth"\s*:\s*")([^"]+)(")"#, "$1***$3"),
            (#"(Bearer\s+)([A-Za-z0-9._\-+=/]+)"#, "$1***"),
            (#"("apiToken"\s*:\s*")([^"]+)(")"#, "$1***$3"),
            (#"("token"\s*:\s*")([^"]+)(")"#, "$1***$3")
        ]
        for (pattern, template) in replacements {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: template
            )
        }
        return result
    }
}
