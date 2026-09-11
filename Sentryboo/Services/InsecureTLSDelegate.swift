import Foundation

/// 仅在用户显式开启「信任此主机证书」时使用；默认不启用。
final class InsecureTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

enum URLSessionFactory {
    static func make(allowInsecureTLS: Bool) -> URLSession {
        if allowInsecureTLS {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 15
            return URLSession(configuration: config, delegate: InsecureTLSDelegate(), delegateQueue: nil)
        }
        return .shared
    }
}
