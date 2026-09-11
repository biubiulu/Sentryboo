import Foundation

/// Zabbix JSON-RPC adapter.
/// - 5.4+ API Token 走 JSON-RPC `auth` 字段（兼容旧版）
/// - 同时附带 `Authorization: Bearer`（兼容 6.x+）
struct ZabbixSource: AlertSource {
    let id: String
    let displayName: String
    let baseURL: String
    let apiToken: String
    let minimumSeverity: AlertSeverity

    private let session: URLSession

    init(
        accountID: UUID,
        displayName: String,
        baseURL: String,
        apiToken: String,
        minimumSeverity: AlertSeverity = .notClassified,
        allowInsecureTLS: Bool = false,
        session: URLSession? = nil
    ) {
        self.id = accountID.uuidString
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiToken = apiToken
        self.minimumSeverity = minimumSeverity
        self.session = session ?? URLSessionFactory.make(allowInsecureTLS: allowInsecureTLS)
    }

    func validate() async throws -> String {
        // apiinfo.version 不需要认证；auth 必须为 null。
        let response: APIInfoVersionResponse = try await post(
            method: "apiinfo.version",
            params: [String: String](),
            auth: .null
        )
        return response.result
    }

    func fetchOpenProblems() async throws -> [AlertProblem] {
        // 对齐 Zabbix 5.4「监视 → 问题 → 最近问题」默认过滤：
        // - recent=true：未恢复 + 近期刚恢复（OK 显示时长内）
        // - suppressed=false：排除维护/抑制问题（前端默认不勾选「显示被抑制的问题」）
        // - sortfield 仅允许 eventid；severity 排序在客户端完成。
        let response: ProblemGetResponse = try await post(
            method: "problem.get",
            params: ProblemGetParams(
                output: ["eventid", "objectid", "name", "severity", "clock", "acknowledged", "r_eventid", "suppressed"],
                recent: true,
                suppressed: false,
                sortfield: ["eventid"],
                sortorder: "DESC",
                selectHosts: ["host", "name"],
                severities: Self.severities(from: minimumSeverity)
            ),
            auth: .token(apiToken)
        )

        return response.result
            // 前端问题页不会展示无主机/已删除主机的残留问题。
            .compactMap { item -> AlertProblem? in
                let hostName = item.hosts?
                    .compactMap { $0.name?.nilIfEmpty ?? $0.host?.nilIfEmpty }
                    .first
                guard let hostName else { return nil }

                let clock = Double(item.clock ?? "0") ?? 0
                let severity = AlertSeverity(rawValue: Int(item.severity ?? "0") ?? 0) ?? .notClassified
                return AlertProblem(
                    id: "\(id):\(item.eventid)",
                    title: item.name ?? "(无标题)",
                    host: hostName,
                    severity: severity,
                    startedAt: Date(timeIntervalSince1970: clock),
                    url: Self.problemWebURL(baseURL: baseURL, eventID: item.eventid, triggerID: item.objectid),
                    acknowledged: item.acknowledged == "1",
                    sourceID: id,
                    sourceName: displayName
                )
            }
            .filter { $0.severity >= minimumSeverity }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity > rhs.severity
                }
                return lhs.startedAt > rhs.startedAt
            }
    }

    /// 打开 Zabbix 前端问题页（兼容常见路径）。
    static func problemWebURL(baseURL: String, eventID: String, triggerID: String?) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        var path = components.path
        if path.hasSuffix("/api_jsonrpc.php") {
            path = String(path.dropLast("/api_jsonrpc.php".count))
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = path.isEmpty ? "" : "/\(path)"
        components.path = "\(prefix)/tr_events.php"
        components.queryItems = [
            URLQueryItem(name: "triggerid", value: triggerID ?? "0"),
            URLQueryItem(name: "eventid", value: eventID)
        ]
        return components.url
    }

    static func frontendBaseURL(from baseURL: String) -> URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        var path = components.path
        if path.hasSuffix("/api_jsonrpc.php") {
            path = String(path.dropLast("/api_jsonrpc.php".count))
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = path.isEmpty ? "/" : "/\(path)/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func severities(from minimum: AlertSeverity) -> [Int] {
        (minimum.rawValue...AlertSeverity.disaster.rawValue).map { $0 }
    }

    private func post<Params: Encodable, Response: Decodable>(
        method: String,
        params: Params,
        auth: JSONRPCAuth
    ) async throws -> Response {
        let url = try apiURL()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json-rpc", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        // 6.x+ 推荐 Bearer；5.4 主要认 JSON auth，两者一起发以兼容。
        if case .token(let token) = auth {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let envelope = JSONRPCRequest(method: method, params: params, auth: auth)
        let bodyData = try JSONEncoder().encode(envelope)
        request.httpBody = bodyData
        await Self.debugRequest(method: method, url: url.absoluteString, bodyData: bodyData)

        let data: Data
        let httpResponse: URLResponse
        do {
            (data, httpResponse) = try await session.data(for: request)
        } catch {
            let mapped = Self.mapTransportError(error)
            await Self.debugError("\(method) 传输失败：\(mapped.localizedDescription)")
            throw mapped
        }

        let statusCode = (httpResponse as? HTTPURLResponse)?.statusCode
        await Self.debugResponse(method: method, statusCode: statusCode, bodyData: data)

        if let http = httpResponse as? HTTPURLResponse {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw SourceError.unauthorized
            }
            if !(200...299).contains(http.statusCode) {
                let preview = Self.responsePreview(data)
                throw SourceError.server("HTTP \(http.statusCode)：\(preview)")
            }
        }

        let jsonData = Self.extractJSONObject(from: data) ?? data

        if let rpcError = try? JSONDecoder().decode(JSONRPCErrorResponse.self, from: jsonData) {
            let message = rpcError.error.detail
            let lowered = message.lowercased()
            if lowered.contains("authoriz") || lowered.contains("token") || lowered.contains("not authorized") {
                throw SourceError.unauthorized
            }
            throw SourceError.server(message)
        }

        do {
            return try JSONDecoder().decode(Response.self, from: jsonData)
        } catch {
            let preview = Self.responsePreview(jsonData)
            if preview.hasPrefix("<!") || preview.lowercased().contains("<html") {
                throw SourceError.server("接口返回了网页而不是 JSON，请确认 Base URL 指向 Zabbix 前端（例如 https://host/zabbix）。预览：\(preview)")
            }
            throw SourceError.server("无法解析响应：\(preview)")
        }
    }

    @MainActor
    private static func debugRequest(method: String, url: String, bodyData: Data) {
        let body = String(data: bodyData, encoding: .utf8) ?? "<binary \(bodyData.count) bytes>"
        DebugLog.shared.request(method: method, url: url, body: body)
    }

    @MainActor
    private static func debugResponse(method: String, statusCode: Int?, bodyData: Data) {
        let body = responsePreview(bodyData, limit: 4000)
        DebugLog.shared.response(method: method, statusCode: statusCode, body: body)
    }

    @MainActor
    private static func debugError(_ message: String) {
        DebugLog.shared.error(message)
    }

    private func apiURL() throws -> URL {
        guard var components = URLComponents(string: baseURL) else {
            throw SourceError.invalidURL
        }
        if components.scheme == nil {
            throw SourceError.invalidURL
        }
        if components.path.hasSuffix("/api_jsonrpc.php") == false {
            let trimmed = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = trimmed.isEmpty ? "/api_jsonrpc.php" : "/\(trimmed)/api_jsonrpc.php"
        }
        guard let url = components.url else {
            throw SourceError.invalidURL
        }
        return url
    }

    /// 部分旧 Zabbix/PHP 会在 JSON 前输出 warning，尽量截出第一个 JSON 对象。
    private static func extractJSONObject(from data: Data) -> Data? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let slice = text[start...end]
        return Data(slice.utf8)
    }

    private static func responsePreview(_ data: Data, limit: Int = 180) -> String {
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            ?? "<非 UTF-8 数据 \(data.count) bytes>"
        if raw.count <= limit { return raw }
        let idx = raw.index(raw.startIndex, offsetBy: limit)
        return String(raw[..<idx]) + "…"
    }

    private static func mapTransportError(_ error: Error) -> SourceError {
        let ns = error as NSError
        let message = error.localizedDescription
        let lowered = message.lowercased()
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorClientCertificateRejected,
                 NSURLErrorSecureConnectionFailed:
                return .certificate
            default:
                break
            }
        }
        if lowered.contains("certificate") || lowered.contains("ssl") || lowered.contains("tls") {
            return .certificate
        }
        return .transport(message)
    }
}

private enum JSONRPCAuth: Encodable {
    case null
    case token(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .token(let value):
            try container.encode(value)
        }
    }
}

private struct JSONRPCRequest<Params: Encodable>: Encodable {
    let jsonrpc = "2.0"
    let method: String
    let params: Params
    let id = 1
    let auth: JSONRPCAuth
}

private struct JSONRPCErrorResponse: Decodable {
    struct RPCError: Decodable {
        let message: String
        let data: FlexibleString?

        var detail: String {
            if let data, !data.value.isEmpty {
                return "\(message)：\(data.value)"
            }
            return message
        }
    }

    let error: RPCError
}

/// Zabbix error.data 可能是 string / number / object，统一转成可读字符串。
private struct FlexibleString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if container.decodeNil() {
            value = ""
        } else if let obj = try? container.decode([String: FlexibleString].self) {
            value = obj.map { "\($0.key)=\($0.value.value)" }.joined(separator: ", ")
        } else {
            value = "（复杂错误详情）"
        }
    }
}

private struct APIInfoVersionResponse: Decodable {
    let result: String
}

private struct ProblemGetParams: Encodable {
    let output: [String]
    let recent: Bool
    let suppressed: Bool
    let sortfield: [String]
    let sortorder: String
    let selectHosts: [String]
    let severities: [Int]
}

private struct ProblemGetResponse: Decodable {
    let result: [ProblemDTO]
}

private struct ProblemDTO: Decodable {
    let eventid: String
    let objectid: String?
    let name: String?
    let severity: String?
    let clock: String?
    let acknowledged: String?
    let rEventID: String?
    let suppressed: String?
    let hosts: [HostDTO]?

    enum CodingKeys: String, CodingKey {
        case eventid, objectid, name, severity, clock, acknowledged, hosts, suppressed
        case rEventID = "r_eventid"
    }
}

private struct HostDTO: Decodable {
    let host: String?
    let name: String?
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
