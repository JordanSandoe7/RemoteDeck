import Foundation

enum XboxAuthError: Error, LocalizedError {
    case noSavedTokens
    case invalidOAuthResponse
    case deviceCodeExpired
    case oauth(String)
    case noXboxUserHash
    case noHomeRegion

    var errorDescription: String? {
        switch self {
        case .noSavedTokens:
            return "Sign in with your Microsoft account to continue."
        case .invalidOAuthResponse:
            return "Microsoft returned an incomplete sign-in response."
        case .deviceCodeExpired:
            return "The sign-in code expired. Start sign-in again."
        case .oauth(let message):
            return "Microsoft sign-in failed: \(message)"
        case .noXboxUserHash:
            return "Xbox authentication did not return an account identifier."
        case .noHomeRegion:
            return "Xbox did not provide a home-streaming region."
        }
    }
}

final class XboxAuthClient {
    static let publicClientID = "1f907974-e22b-4810-a9de-d9647380c97e"
    private let http: XboxHTTPClient
    private let tokenStore: KeychainTokenStore

    init(http: XboxHTTPClient = XboxHTTPClient(), tokenStore: KeychainTokenStore = KeychainTokenStore()) {
        self.http = http
        self.tokenStore = tokenStore
    }

    func requestDeviceCode() async throws -> DeviceCodeResponse {
        let request = Self.formRequest(
            url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!,
            fields: [
                "client_id": Self.publicClientID,
                "scope": "xboxlive.signin openid profile offline_access"
            ]
        )
        return try await http.decode(DeviceCodeResponse.self, from: request)
    }

    func pollForDeviceCode(_ deviceCode: DeviceCodeResponse) async throws -> OAuthTokenSet {
        let deadline = Date().addingTimeInterval(TimeInterval(deviceCode.expiresIn))
        var interval = max(1, deviceCode.interval)
        var consecutiveNetworkFailures = 0
        let endpoint = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!
        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            let request = Self.formRequest(
                url: endpoint,
                fields: [
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                    "client_id": Self.publicClientID,
                    "device_code": deviceCode.deviceCode
                ]
            )
            do {
                let result = try await http.send(request)
                let payload = try JSONDecoder().decode(OAuthTokenPayload.self, from: result.data)
                let tokens = OAuthTokenSet(payload: payload)
                try tokenStore.save(tokens)
                return tokens
            } catch let error as XboxServiceError {
                consecutiveNetworkFailures = 0
                switch error.code {
                case "authorization_pending":
                    continue
                case "slow_down":
                    interval += 5
                case "authorization_declined":
                    throw XboxAuthError.oauth("You declined the sign-in request.")
                case "expired_token":
                    throw XboxAuthError.deviceCodeExpired
                default:
                    throw error
                }
            } catch let error as DecodingError {
                throw error
            } catch {
                guard XboxHTTPClient.isTransientNetworkError(error) else {
                    throw error
                }
                consecutiveNetworkFailures += 1
                guard consecutiveNetworkFailures < 3 else {
                    throw error
                }
                interval = min(max(interval, 5) * 2, 30)
            }
        }
        throw XboxAuthError.deviceCodeExpired
    }

    func currentContext() async throws -> XboxAuthContext {
        guard let stored = try tokenStore.load() else {
            throw XboxAuthError.noSavedTokens
        }
        let oauth = try await validOAuthTokens(stored)
        let userToken = try await xboxUserToken(accessToken: oauth.accessToken)
        let webToken = try await xstsToken(userToken: userToken.token, relyingParty: "http://xboxlive.com")
        let gssvToken = try await xstsToken(userToken: userToken.token, relyingParty: "http://gssv.xboxlive.com/")
        let homeToken = try await homeStreamingToken(gssvToken: gssvToken.token)
        guard let region = homeToken.offeringSettings?.regions?.first(where: \.isDefault)
                ?? homeToken.offeringSettings?.regions?.first else {
            throw XboxAuthError.noHomeRegion
        }
        guard region.baseURI.scheme == "https",
              region.baseURI.host?.hasSuffix(".core.gssv-play-prodxhome.xboxlive.com") == true else {
            throw URLError(.unsupportedURL)
        }
        return XboxAuthContext(
            oauth: oauth,
            userToken: userToken,
            webToken: webToken,
            gssvToken: gssvToken,
            homeToken: homeToken,
            regionBaseURI: region.baseURI
        )
    }

    func transferToken() async throws -> String {
        guard let stored = try tokenStore.load() else {
            throw XboxAuthError.noSavedTokens
        }
        let oauth = try await validOAuthTokens(stored)
        let request = Self.formRequest(
            url: URL(string: "https://login.live.com/oauth20_token.srf")!,
            fields: [
                "client_id": Self.publicClientID,
                "grant_type": "refresh_token",
                "refresh_token": oauth.refreshToken,
                "scope": "service::http://Passport.NET/purpose::PURPOSE_XBOX_CLOUD_CONSOLE_TRANSFER_TOKEN"
            ]
        )
        let data = try await http.send(request).data
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let transferToken = payload["access_token"] as? String,
              !transferToken.isEmpty else {
            throw XboxAuthError.invalidOAuthResponse
        }
        return transferToken
    }

    func signOut() throws {
        try tokenStore.delete()
    }

    private func validOAuthTokens(_ current: OAuthTokenSet) async throws -> OAuthTokenSet {
        guard !current.isValid() else { return current }
        let request = Self.formRequest(
            url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!,
            fields: [
                "client_id": Self.publicClientID,
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "scope": "xboxlive.signin openid profile offline_access"
            ]
        )
        let payload = try await http.decode(OAuthTokenPayload.self, from: request)
        let refreshed = OAuthTokenSet(payload: payload)
        try tokenStore.save(refreshed)
        return refreshed
    }

    private func xboxUserToken(accessToken: String) async throws -> XboxTokenResponse {
        let body: [String: Any] = [
            "Properties": [
                "AuthMethod": "RPS",
                "SiteName": "user.auth.xboxlive.com",
                "RpsTicket": "d=\(accessToken)"
            ],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT"
        ]
        return try await http.decode(
            XboxTokenResponse.self,
            from: try jsonRequest(
                url: URL(string: "https://user.auth.xboxlive.com/user/authenticate")!,
                body: body,
                headers: ["x-xbl-contract-version": "1"]
            )
        )
    }

    private func xstsToken(userToken: String, relyingParty: String) async throws -> XboxTokenResponse {
        let body: [String: Any] = [
            "Properties": [
                "SandboxId": "RETAIL",
                "UserTokens": [userToken]
            ],
            "RelyingParty": relyingParty,
            "TokenType": "JWT"
        ]
        return try await http.decode(
            XboxTokenResponse.self,
            from: try jsonRequest(
                url: URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!,
                body: body,
                headers: ["x-xbl-contract-version": "1"]
            )
        )
    }

    private func homeStreamingToken(gssvToken: String) async throws -> XHomeTokenResponse {
        let request = try jsonRequest(
            url: URL(string: "https://xhome.gssv-play-prod.xboxlive.com/v2/login/user")!,
            body: ["token": gssvToken, "offeringId": "xhome"],
            headers: ["x-gssv-client": "XboxComBrowser"]
        )
        return try await http.decode(XHomeTokenResponse.self, from: request)
    }

    static func formRequest(url: URL, fields: [String: String]) -> URLRequest {
        var components = URLComponents()
        components.queryItems = fields.keys.sorted().map {
            URLQueryItem(name: $0, value: fields[$0])
        }
        let body = (components.percentEncodedQuery ?? "").replacingOccurrences(of: "%20", with: "+")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store, must-revalidate, no-cache", forHTTPHeaderField: "Cache-Control")
        request.httpBody = body.data(using: .utf8)
        return request
    }

    private func jsonRequest(url: URL, body: [String: Any], headers: [String: String] = [:]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store, must-revalidate, no-cache", forHTTPHeaderField: "Cache-Control")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
