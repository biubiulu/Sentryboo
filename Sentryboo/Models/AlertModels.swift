import Foundation
import SwiftUI

struct AlertProblem: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let host: String
    let severity: AlertSeverity
    let startedAt: Date
    let url: URL?
    let acknowledged: Bool
}

enum AlertSeverity: Int, Comparable, CaseIterable, Sendable {
    case notClassified = 0
    case information = 1
    case warning = 2
    case average = 3
    case high = 4
    case disaster = 5

    static func < (lhs: AlertSeverity, rhs: AlertSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .notClassified: return "未分类"
        case .information: return "信息"
        case .warning: return "警告"
        case .average: return "一般严重"
        case .high: return "严重"
        case .disaster: return "灾难"
        }
    }

    var color: Color {
        switch self {
        case .notClassified: return .gray
        case .information: return .blue
        case .warning: return .yellow
        case .average: return .orange
        case .high: return .red
        case .disaster: return .purple
        }
    }
}

enum SourceStatus: Equatable {
    case idle
    case syncing
    case ok(count: Int)
    case error(String)
}

enum SourceError: LocalizedError {
    case notConfigured
    case invalidURL
    case unauthorized
    case certificate
    case transport(String)
    case decoding
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "尚未配置 Zabbix URL 或 API Token。"
        case .invalidURL:
            return "Zabbix Base URL 无效。"
        case .unauthorized:
            return "API Token 无效或权限不足。"
        case .certificate:
            return "证书不受信任。若为内网自签证书，请在设置中开启「信任此主机证书」。"
        case .transport(let message):
            return "无法连接 Zabbix：\(message)"
        case .decoding:
            return "Zabbix 返回了无法解析的数据。请确认 Base URL 正确，且服务器是 Zabbix 5.4+。"
        case .server(let message):
            return "Zabbix 返回错误：\(message)"
        }
    }
}
