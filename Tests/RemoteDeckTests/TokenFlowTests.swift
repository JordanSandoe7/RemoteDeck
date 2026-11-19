import Foundation
import XCTest
@testable import RemoteDeck

final class TokenFlowTests: XCTestCase {
    func testDeviceCodeRequestUsesPublicClientAndExpectedScope() throws {
        let endpoint = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")!
        let request = XboxAuthClient.formRequest(
            url: endpoint,
            fields: [
                "client_id": XboxAuthClient.publicClientID,
                "scope": "xboxlive.signin openid profile offline_access"
            ]
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = try XCTUnwrap(request.httpBody)
        let query = URLComponents(string: "https://example.invalid/?\(String(decoding: body, as: UTF8.self))")?.queryItems
        let fields = Dictionary(uniqueKeysWithValues: try XCTUnwrap(query).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(fields["client_id"], XboxAuthClient.publicClientID)
        XCTAssertEqual(fields["scope"], "xboxlive.signin openid profile offline_access")
        XCTAssertNil(fields["client_secret"])
    }

    func testDeviceTokenRequestUsesDeviceCodeGrant() throws {
        let endpoint = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!
        let request = XboxAuthClient.formRequest(
            url: endpoint,
            fields: [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": XboxAuthClient.publicClientID,
                "device_code": "device-code-value"
            ]
        )
        let body = try XCTUnwrap(request.httpBody)
        let query = URLComponents(string: "https://example.invalid/?\(String(decoding: body, as: UTF8.self))")?.queryItems
        let fields = Dictionary(uniqueKeysWithValues: try XCTUnwrap(query).map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(fields["grant_type"], "urn:ietf:params:oauth:grant-type:device_code")
        XCTAssertEqual(fields["device_code"], "device-code-value")
        XCTAssertEqual(fields["client_id"], XboxAuthClient.publicClientID)
    }

    func testOAuthDevicePollingErrorsAreRecognized() throws {
        let data = Data(#"{"error":"authorization_pending","error_description":"The request is still pending."}"#.utf8)
        let error = XboxHTTPClient.serviceError(data: data, status: 400)

        XCTAssertEqual(error.code, "authorization_pending")
        XCTAssertEqual(error.serverMessage, "The request is still pending.")
    }

    func testOAuthTokenSetUsesExpiryAndRefreshToken() throws {
        let data = Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600}"#.utf8)
        let payload = try JSONDecoder().decode(OAuthTokenPayload.self, from: data)
        let now = Date(timeIntervalSince1970: 1_000)
        let tokens = OAuthTokenSet(payload: payload, now: now)

        XCTAssertEqual(tokens.accessToken, "access")
        XCTAssertEqual(tokens.refreshToken, "refresh")
        XCTAssertEqual(tokens.expiresAt, now.addingTimeInterval(3600))
        XCTAssertTrue(tokens.isValid(at: now))
        XCTAssertFalse(tokens.isValid(at: now.addingTimeInterval(3600)))
    }
}
