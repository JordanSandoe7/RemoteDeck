import Foundation

struct StreamPreferences {
    let resolution: Int
    let bitrateKbps: Int
    let locale: String
}

struct RemoteStreamSession {
    let id: String
    let baseURI: URL
    let configuration: SessionConfiguration
}

enum SessionSignalingError: Error, LocalizedError {
    case invalidSessionResponse
    case failed(String?)
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidSessionResponse:
            return "Xbox returned an invalid streaming session response."
        case .failed(let reason):
            let detail = reason.map { " Xbox reported: \($0)" } ?? ""
            return "Xbox could not provision the stream. Check that the console is online, Remote Features is enabled, and power mode is set to Instant-On.\(detail)"
        case .timeout:
            return "Xbox did not finish preparing the stream in time. Check console power and your network."
        }
    }
}

final class SessionSignalingService {
    private let http: XboxHTTPClient
    private let auth: XboxAuthClient
    private var resolution = 1080

    init(http: XboxHTTPClient = XboxHTTPClient(), auth: XboxAuthClient) {
        self.http = http
        self.auth = auth
    }

    func start(
        console: XboxConsole,
        context: XboxAuthContext,
        preferences: StreamPreferences
    ) async throws -> RemoteStreamSession {
        resolution = preferences.resolution
        let startURL = endpoint(["v5", "sessions", "home", "play"], baseURI: context.regionBaseURI)
        let osName = preferences.resolution >= 1080 ? "windows" : "android"
        let body: [String: Any] = [
            "clientSessionId": "",
            "titleId": "",
            "systemUpdateGroup": "",
            "settings": [
                "nanoVersion": "V3;WebrtcTransport.dll",
                "enableOptionalDataCollection": false,
                "enableTextToSpeech": false,
                "highContrast": 0,
                "locale": preferences.locale,
                "useIceConnection": false,
                "timezoneOffsetMinutes": 120,
                "sdkType": "web",
                "osName": osName
            ],
            "serverId": console.serverId,
            "fallbackRegionNames": []
        ]
        var request = URLRequest(url: startURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            try ConsoleService.deviceInfo(resolution: preferences.resolution),
            forHTTPHeaderField: "X-MS-Device-Info"
        )
        request.setValue("XboxComBrowser", forHTTPHeaderField: "X-Gssv-Client")
        request.setValue("Bearer \(context.homeToken.gsToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let startResponse = try await http.decode(SessionStartResponse.self, from: request)
        let id = startResponse.sessionId ?? startResponse.sessionPath.split(separator: "/").last.map(String.init)
        guard let id, !id.isEmpty else {
            throw SessionSignalingError.invalidSessionResponse
        }

        do {
            try await waitUntilReady(sessionID: id, baseURI: context.regionBaseURI, token: context.homeToken.gsToken)
            let configuration = try await fetchConfiguration(
                sessionID: id,
                baseURI: context.regionBaseURI,
                token: context.homeToken.gsToken
            )
            return RemoteStreamSession(id: id, baseURI: context.regionBaseURI, configuration: configuration)
        } catch let startError {
            do {
                try await stop(sessionID: id, baseURI: context.regionBaseURI, token: context.homeToken.gsToken)
            } catch let cleanupError {
                throw SessionSignalingError.failed(
                    "\(startError.localizedDescription) Session cleanup also failed: \(cleanupError.localizedDescription)"
                )
            }
            throw startError
        }
    }

    func exchangeSDP(
        _ sdp: String,
        session: RemoteStreamSession,
        token: String
    ) async throws -> String {
        let body: [String: Any] = [
            "messageType": "offer",
            "requestId": 1,
            "sdp": sdp,
            "configuration": [
                "chatConfiguration": [
                    "bytesPerSample": 2,
                    "expectedClipDurationMs": 20,
                    "format": ["codec": "opus", "container": "webm"],
                    "numChannels": 1,
                    "sampleFrequencyHz": 24000
                ],
                "chat": ["minVersion": 1, "maxVersion": 1],
                "control": ["minVersion": 1, "maxVersion": 3],
                "input": ["minVersion": 1, "maxVersion": 9],
                "reliableinput": ["minVersion": 9, "maxVersion": 9],
                "unreliableinput": ["minVersion": 9, "maxVersion": 9],
                "message": ["minVersion": 1, "maxVersion": 1]
            ]
        ]
        try await postJSON(body, to: sessionURL(session, path: "sdp"), token: token)
        let exchange = try await waitForExchange(path: "sdp", session: session, token: token)
        guard let response = exchange.exchangeResponse,
              let data = response.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answer = object["sdp"] as? String else {
            throw SessionSignalingError.invalidSessionResponse
        }
        return answer
    }

    func exchangeICE(
        _ candidates: [[String: Any]],
        session: RemoteStreamSession,
        token: String
    ) async throws -> [[String: Any]] {
        try await postJSON(
            ["candidates": candidates],
            to: sessionURL(session, path: "ice"),
            token: token
        )
        let exchange = try await waitForExchange(path: "ice", session: session, token: token)
        guard let response = exchange.exchangeResponse,
              let data = response.data(using: .utf8) else {
            throw SessionSignalingError.invalidSessionResponse
        }
        let parsed = try JSONSerialization.jsonObject(with: data)
        if let candidates = parsed as? [[String: Any]] {
            return candidates
        }
        if let keyed = parsed as? [String: [String: Any]] {
            return keyed.keys.sorted().compactMap { keyed[$0] }
        }
        throw SessionSignalingError.invalidSessionResponse
    }

    func keepAlive(session: RemoteStreamSession, token: String) async throws {
        try await postJSON([String: String](), to: sessionURL(session, path: "keepalive"), token: token)
    }

    func stop(sessionID: String, baseURI: URL, token: String) async throws {
        let url = endpoint(["v5", "sessions", "home", sessionID], baseURI: baseURI)
        var request = try authorizedRequest(url: url, token: token)
        request.httpMethod = "DELETE"
        _ = try await http.send(request)
    }

    private func waitUntilReady(sessionID: String, baseURI: URL, token: String) async throws {
        let deadline = Date().addingTimeInterval(180)
        var didConnect = false
        while Date() < deadline {
            try Task.checkCancellation()
            let url = endpoint(["v5", "sessions", "home", sessionID, "state"], baseURI: baseURI)
            let response = try await http.decode(
                SessionStateResponse.self,
                from: authorizedRequest(url: url, token: token)
            )
            switch response.state {
            case "Provisioned":
                return
            case "New", "WaitingForResources", "Provisioning":
                break
            case "ReadyToConnect":
                if !didConnect {
                    let transferToken = try await auth.transferToken()
                    try await postJSON(
                        ["userToken": transferToken],
                        to: endpoint(["v5", "sessions", "home", sessionID, "connect"], baseURI: baseURI),
                        token: token
                    )
                    didConnect = true
                }
            case "Failed", "Error":
                throw SessionSignalingError.failed(response.errorDetails?.message ?? response.errorDetails?.code)
            default:
                throw SessionSignalingError.failed("Unexpected session state: \(response.state)")
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw SessionSignalingError.timeout
    }

    private func fetchConfiguration(sessionID: String, baseURI: URL, token: String) async throws -> SessionConfiguration {
        let url = endpoint(["v5", "sessions", "home", sessionID, "configuration"], baseURI: baseURI)
        return try await http.decode(
            SessionConfiguration.self,
            from: authorizedRequest(url: url, token: token)
        )
    }

    private func waitForExchange(
        path: String,
        session: RemoteStreamSession,
        token: String
    ) async throws -> ExchangeResponse {
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            try Task.checkCancellation()
            let request = try authorizedRequest(url: sessionURL(session, path: path), token: token)
            let response = try await http.send(request)
            if response.response.statusCode != 204, !response.data.isEmpty {
                let exchange = try JSONDecoder().decode(ExchangeResponse.self, from: response.data)
                if exchange.exchangeResponse != nil {
                    return exchange
                }
                if let message = exchange.errorDetails?.message {
                    throw SessionSignalingError.failed(message)
                }
            }
            try await Task.sleep(nanoseconds: 750_000_000)
        }
        throw SessionSignalingError.timeout
    }

    private func postJSON(_ body: [String: Any], to url: URL, token: String) async throws {
        var request = try authorizedRequest(url: url, token: token)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await http.send(request)
    }

    private func authorizedRequest(url: URL, token: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("XboxComBrowser", forHTTPHeaderField: "X-Gssv-Client")
        request.setValue(
            try ConsoleService.deviceInfo(resolution: resolution),
            forHTTPHeaderField: "X-MS-Device-Info"
        )
        return request
    }

    private func sessionURL(_ session: RemoteStreamSession, path: String) -> URL {
        endpoint(["v5", "sessions", "home", session.id, path], baseURI: session.baseURI)
    }

    private func endpoint(_ components: [String], baseURI: URL) -> URL {
        components.reduce(baseURI) { $0.appendingPathComponent($1) }
    }

}
