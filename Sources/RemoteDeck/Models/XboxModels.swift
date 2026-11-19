import Foundation

struct DeviceCodeResponse: Decodable, Equatable {
    let userCode: String
    let deviceCode: String
    let verificationURI: URL
    let expiresIn: Int
    let interval: Int
    let message: String?

    enum CodingKeys: String, CodingKey {
        case userCode = "user_code"
        case deviceCode = "device_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case message
    }
}

struct OAuthTokenPayload: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct OAuthTokenSet: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date

    init(payload: OAuthTokenPayload, now: Date = Date()) {
        accessToken = payload.accessToken
        refreshToken = payload.refreshToken
        expiresAt = now.addingTimeInterval(TimeInterval(payload.expiresIn))
    }

    func isValid(at date: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(date) > 60
    }
}

struct XboxTokenResponse: Decodable {
    let token: String
    let displayClaims: XboxDisplayClaims?
    let notAfter: String?

    enum CodingKeys: String, CodingKey {
        case token = "Token"
        case displayClaims = "DisplayClaims"
        case notAfter = "NotAfter"
    }
}

struct XboxDisplayClaims: Decodable {
    let xui: [XboxUserClaim]?

    enum CodingKeys: String, CodingKey {
        case xui
    }
}

struct XboxUserClaim: Decodable {
    let userHash: String?
    let xuid: String?

    enum CodingKeys: String, CodingKey {
        case userHash = "uhs"
        case xuid = "xid"
    }
}

struct XHomeTokenResponse: Decodable {
    let gsToken: String
    let durationInSeconds: Int?
    let offeringSettings: OfferingSettings?
}

struct OfferingSettings: Decodable {
    let regions: [XboxRegion]?
}

struct XboxRegion: Decodable {
    let name: String?
    let baseURI: URL
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case baseURI = "baseUri"
        case isDefault
    }
}

struct XboxConsole: Decodable, Identifiable, Hashable {
    let serverId: String
    let deviceName: String
    let powerState: String?
    let consoleType: String?
    let playPath: String?
    let outOfHomeWarning: Bool?
    let wirelessWarning: Bool?

    var id: String { serverId }

    enum CodingKeys: String, CodingKey {
        case serverId
        case deviceName
        case powerState
        case consoleType
        case playPath
        case outOfHomeWarning
        case wirelessWarning
    }
}

struct ConsoleListResponse: Decodable {
    let totalItems: Int?
    let results: [XboxConsole]
    let continuationToken: String?
}

struct SessionStartResponse: Decodable {
    let sessionId: String?
    let sessionPath: String
    let state: String
}

struct SessionStateResponse: Decodable {
    let state: String
    let detailedSessionState: Int?
    let errorDetails: ServiceErrorDetails?
}

struct ServiceErrorDetails: Decodable {
    let code: String?
    let message: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let stringCode = try? container.decode(String.self, forKey: .code) {
            code = stringCode
        } else if let numericCode = try? container.decode(Int.self, forKey: .code) {
            code = String(numericCode)
        } else {
            code = nil
        }
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }
}

struct SessionConfiguration: Decodable {
    let keepAlivePulseInSeconds: Int?
    let serverDetails: ServerDetails?
}

struct ServerDetails: Decodable {
    let ipAddress: String?
    let port: Int?
    let iceExchangePath: String?
}

struct ExchangeResponse: Decodable {
    let exchangeResponse: String?
    let errorDetails: ServiceErrorDetails?
}

struct XboxAuthContext {
    let oauth: OAuthTokenSet
    let userToken: XboxTokenResponse
    let webToken: XboxTokenResponse
    let gssvToken: XboxTokenResponse
    let homeToken: XHomeTokenResponse
    let regionBaseURI: URL

    var userHash: String? {
        webToken.displayClaims?.xui?.first?.userHash
    }
}
