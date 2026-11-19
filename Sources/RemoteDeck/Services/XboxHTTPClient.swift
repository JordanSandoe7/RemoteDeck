import Foundation

struct XboxHTTPResult {
    let data: Data
    let response: HTTPURLResponse
}

struct XboxServiceError: Error, LocalizedError {
    let statusCode: Int
    let code: String?
    let serverMessage: String?

    var errorDescription: String? {
        let detail = [code, serverMessage].compactMap { $0 }.joined(separator: ": ")
        if detail.isEmpty {
            return "Xbox service returned HTTP \(statusCode)."
        }
        return "Xbox service returned HTTP \(statusCode) (\(detail))."
    }
}

final class XboxHTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ request: URLRequest) async throws -> XboxHTTPResult {
        guard request.url?.scheme == "https",
              let host = request.url?.host?.lowercased(),
              host == "login.microsoftonline.com" ||
              host == "login.live.com" ||
              host == "device.auth.xboxlive.com" ||
              host == "user.auth.xboxlive.com" ||
              host == "xsts.auth.xboxlive.com" ||
              host == "xhome.gssv-play-prod.xboxlive.com" ||
              host == "xccs.xboxlive.com" ||
              host.hasSuffix(".core.gssv-play-prodxhome.xboxlive.com") else {
            throw URLError(.unsupportedURL)
        }

        let retryable = Self.isRetryable(request)
        var retryCount = 0
        while true {
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200..<300).contains(httpResponse.statusCode) else {
                    let error = Self.serviceError(data: data, status: httpResponse.statusCode)
                    guard retryable,
                          Self.isTransientServerStatus(httpResponse.statusCode),
                          retryCount < 2 else {
                        throw error
                    }
                    try await Task.sleep(nanoseconds: Self.retryDelay(retryCount))
                    retryCount += 1
                    continue
                }
                return XboxHTTPResult(data: data, response: httpResponse)
            } catch {
                guard retryable,
                      Self.isTransientNetworkError(error),
                      retryCount < 2 else {
                    throw error
                }
                try await Task.sleep(nanoseconds: Self.retryDelay(retryCount))
                retryCount += 1
            }
        }
    }

    func decode<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let result = try await send(request)
        return try JSONDecoder().decode(type, from: result.data)
    }

    static func serviceError(data: Data, status: Int) -> XboxServiceError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let nested = object?["errorDetails"] as? [String: Any]
        let code = (nested?["code"] as? String)
            ?? (object?["code"] as? String)
            ?? (object?["error"] as? String)
            ?? (object?["XErr"].map { String(describing: $0) })
        let message = (nested?["message"] as? String)
            ?? (object?["error_description"] as? String)
            ?? (object?["message"] as? String)
            ?? (object?["Message"] as? String)
            ?? (object?["errorMessage"] as? String)
        return XboxServiceError(statusCode: status, code: code, serverMessage: message)
    }

    static func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
             .dnsLookupFailed, .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    private static func isRetryable(_ request: URLRequest) -> Bool {
        let method = request.httpMethod?.uppercased() ?? "GET"
        if ["GET", "HEAD", "DELETE"].contains(method) {
            return true
        }
        guard method == "POST",
              let host = request.url?.host?.lowercased(),
              let path = request.url?.path else {
            return false
        }
        switch host {
        case "login.microsoftonline.com":
            return path == "/consumers/oauth2/v2.0/devicecode"
                || path == "/consumers/oauth2/v2.0/token"
        case "login.live.com":
            return path == "/oauth20_token.srf"
        case "user.auth.xboxlive.com":
            return path == "/user/authenticate"
        case "xsts.auth.xboxlive.com":
            return path == "/xsts/authorize"
        case "xhome.gssv-play-prod.xboxlive.com":
            return path == "/v2/login/user"
        case "xccs.xboxlive.com":
            return path == "/commands"
        default:
            return host.hasSuffix(".core.gssv-play-prodxhome.xboxlive.com")
                && path.hasSuffix("/keepalive")
        }
    }

    private static func isTransientServerStatus(_ statusCode: Int) -> Bool {
        [408, 429, 500, 502, 503, 504].contains(statusCode)
    }

    private static func retryDelay(_ retryCount: Int) -> UInt64 {
        500_000_000 * UInt64(1 << retryCount)
    }
}
