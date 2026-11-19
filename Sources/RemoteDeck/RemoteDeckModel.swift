import Combine
import Foundation
import SwiftUI

@MainActor
final class RemoteDeckModel: ObservableObject {
    @Published private(set) var deviceCode: DeviceCodeResponse?
    @Published private(set) var consoles: [XboxConsole] = []
    @Published private(set) var selectedConsole: XboxConsole?
    @Published private(set) var transport: WebRTCTransport?
    @Published private(set) var hasSavedTokens = false
    @Published private(set) var isBusy = false
    @Published private(set) var isStreaming = false
    @Published private(set) var signInStatus: String?
    @Published var errorMessage: String?
    @Published var resolution = 1080
    @Published var bitrateKbps = 12000
    @Published var showTouchControls = true

    let controller = GameControllerInput()
    let auth = XboxAuthClient()
    private let consoleService = ConsoleService()
    private var context: XboxAuthContext?
    private var activeSession: RemoteStreamSession?
    private var sessionService: SessionSignalingService?
    private var signInTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?

    init() {
        do {
            hasSavedTokens = try KeychainTokenStore().load() != nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginSignIn() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        signInStatus = "Requesting a Microsoft sign-in code…"
        defer { isBusy = false }
        do {
            let code = try await auth.requestDeviceCode()
            deviceCode = code
            signInStatus = "Waiting for approval. Return to RemoteDeck after approving."
            signInTask?.cancel()
            signInTask = Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await self.auth.pollForDeviceCode(code)
                    self.signInStatus = "Approved. Finishing Xbox sign-in…"
                    self.hasSavedTokens = true
                    self.deviceCode = nil
                    await self.loadConsoles()
                    self.signInStatus = nil
                } catch is CancellationError {
                } catch {
                    self.deviceCode = nil
                    self.signInStatus = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        } catch {
            signInStatus = nil
            errorMessage = error.localizedDescription
        }
    }

    func loadConsoles() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let newContext = try await auth.currentContext()
            context = newContext
            consoles = try await consoleService.consoles(using: newContext)
            deviceCode = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connect(to console: XboxConsole) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let newContext = try await auth.currentContext()
            context = newContext
            if let state = console.powerState?.lowercased(),
               state.contains("off") || state.contains("standby") {
                try await consoleService.wake(console, using: newContext)
                try await Task.sleep(nanoseconds: 12_000_000_000)
            }
            let service = SessionSignalingService(auth: auth)
            sessionService = service
            let session = try await service.start(
                console: console,
                context: newContext,
                preferences: StreamPreferences(
                    resolution: resolution,
                    bitrateKbps: bitrateKbps,
                    locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-")
                )
            )
            activeSession = session
            let newTransport = WebRTCTransport(
                input: controller,
                bitrateKbps: bitrateKbps,
                resolution: resolution
            )
            newTransport.onReconnectRequested = { [weak self] in
                Task { @MainActor in
                    await self?.reconnect()
                }
            }
            transport = newTransport
            try await newTransport.connect(
                session: session,
                token: newContext.homeToken.gsToken,
                signaling: service
            )
            selectedConsole = console
            isStreaming = true
            startKeepAlive()
        } catch {
            errorMessage = Self.friendlyError(error)
            await disconnect()
        }
    }

    func disconnect() async {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        transport?.onReconnectRequested = nil
        transport?.close()
        transport = nil
        isStreaming = false
        selectedConsole = nil
        if let activeSession, let context, let sessionService {
            do {
                try await sessionService.stop(
                    sessionID: activeSession.id,
                    baseURI: activeSession.baseURI,
                    token: context.homeToken.gsToken
                )
            } catch {
                errorMessage = "The stream ended, but Xbox could not confirm session cleanup: \(error.localizedDescription)"
            }
        }
        activeSession = nil
    }

    func signOut() {
        signInTask?.cancel()
        do {
            try auth.signOut()
            hasSavedTokens = false
            context = nil
            consoles = []
            deviceCode = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,
                      let session = self.activeSession,
                      let context = self.context,
                      let service = self.sessionService else {
                    return
                }
                do {
                    let pulse = min(120, max(5, session.configuration.keepAlivePulseInSeconds ?? 30))
                    try await Task.sleep(nanoseconds: UInt64(pulse) * 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    try await service.keepAlive(session: session, token: context.homeToken.gsToken)
                } catch is CancellationError {
                    return
                } catch {
                    self.errorMessage = "Xbox session keepalive failed: \(error.localizedDescription)"
                    return
                }
            }
        }
    }

    private func reconnect() async {
        guard let console = selectedConsole else { return }
        await disconnect()
        await connect(to: console)
    }

    private static func friendlyError(_ error: Error) -> String {
        let detail = error.localizedDescription
        let lowercased = detail.lowercased()
        if lowercased.contains("timed out") || lowercased.contains("network") {
            return "\(detail) Check your iPhone and Xbox network connection, and make sure Xbox Remote Features is enabled."
        }
        if lowercased.contains("provision") || lowercased.contains("instant-on") {
            return detail
        }
        return detail
    }
}
