import Foundation

final class ConsoleService {
    private let http: XboxHTTPClient

    init(http: XboxHTTPClient = XboxHTTPClient()) {
        self.http = http
    }

    func consoles(using context: XboxAuthContext) async throws -> [XboxConsole] {
        let url = context.regionBaseURI
            .appendingPathComponent("v6")
            .appendingPathComponent("servers")
            .appendingPathComponent("home")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(context.homeToken.gsToken)", forHTTPHeaderField: "Authorization")
        request.setValue("XboxComBrowser", forHTTPHeaderField: "X-Gssv-Client")
        request.setValue(try Self.deviceInfo(), forHTTPHeaderField: "X-MS-Device-Info")
        let response = try await http.decode(ConsoleListResponse.self, from: request)
        return response.results
    }

    func wake(_ console: XboxConsole, using context: XboxAuthContext) async throws {
        guard let userHash = context.userHash else {
            throw XboxAuthError.noXboxUserHash
        }
        let url = URL(string: "https://xccs.xboxlive.com/commands")!
        let body: [String: Any] = [
            "destination": "Xbox",
            "type": "Power",
            "command": "WakeUp",
            "sessionId": UUID().uuidString,
            "sourceId": "com.microsoft.smartglass",
            "parameters": [],
            "linkedXboxId": console.serverId
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("XBL3.0 x=\(userHash);\(context.webToken.token)", forHTTPHeaderField: "Authorization")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        request.setValue("RemoteManagement", forHTTPHeaderField: "skillplatform")
        request.setValue("4", forHTTPHeaderField: "x-xbl-contract-version")
        request.setValue("XboxApp", forHTTPHeaderField: "x-xbl-client-name")
        request.setValue("UWA", forHTTPHeaderField: "x-xbl-client-type")
        request.setValue("39.39.22001.0", forHTTPHeaderField: "x-xbl-client-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await http.send(request)
    }

    static func deviceInfo(resolution: Int = 1080) throws -> String {
        let width = resolution >= 1080 ? 1920 : 1280
        let height = resolution >= 1080 ? 1080 : 720
        let value: [String: Any] = [
            "appInfo": [
                "env": [
                    "clientAppId": "www.xbox.com",
                    "clientAppType": "browser",
                    "clientAppVersion": "26.1.97",
                    "clientSdkVersion": "10.3.7",
                    "httpEnvironment": "prod",
                    "sdkInstallId": ""
                ]
            ],
            "dev": [
                "hw": [
                    "make": "Microsoft",
                    "model": "unknown",
                    "sdktype": "web"
                ],
                "os": [
                    "name": resolution >= 1080 ? "windows" : "android",
                    "ver": "22631.2715",
                    "platform": "desktop"
                ],
                "displayInfo": [
                    "dimensions": [
                        "widthInPixels": width,
                        "heightInPixels": height
                    ],
                    "pixelDensity": [
                        "dpiX": 2,
                        "dpiY": 2
                    ]
                ],
                "browser": [
                    "browserName": "chrome",
                    "browserVersion": "130.0"
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: value)
        return String(decoding: data, as: UTF8.self)
    }
}
