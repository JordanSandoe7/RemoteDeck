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

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw Self.serviceError(data: data, status: httpResponse.statusCode)
        }
        return XboxHTTPResult(data: data, response: httpResponse)
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
}
