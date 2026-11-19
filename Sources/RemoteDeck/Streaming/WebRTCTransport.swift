import AVFoundation
import Combine
import Foundation
import WebRTC

final class WebRTCTransport: NSObject, ObservableObject {
    @Published private(set) var videoTrack: RTCVideoTrack?
    @Published private(set) var connectionState = "Preparing"
    @Published private(set) var latencyMilliseconds: Int?
    @Published private(set) var framesPerSecond: Int?
    @Published private(set) var isInputReady = false

    var onReconnectRequested: (() -> Void)?

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory(
            encoderFactory: RTCDefaultVideoEncoderFactory(),
            decoderFactory: RTCDefaultVideoDecoderFactory()
        )
    }()

    private let input: GameControllerInput
    private let bitrateKbps: Int
    private let resolution: Int
    private var peerConnection: RTCPeerConnection?
    private var channels: [String: RTCDataChannel] = [:]
    private var localCandidates: [RTCIceCandidate] = []
    private var candidateWaiter: CheckedContinuation<[RTCIceCandidate], Never>?
    private var inputTimer: Timer?
    private var statsTimer: Timer?
    private var sequence: UInt32 = 0
    private var signaling: SessionSignalingService?
    private var session: RemoteStreamSession?
    private var token = ""
    private var closed = false
    private var reconnectTask: Task<Void, Never>?
    private var handshakeAcknowledged = false
    private var handshakeCompleted = false
    private var didSendInputMetadata = false

    init(input: GameControllerInput, bitrateKbps: Int, resolution: Int) {
        self.input = input
        self.bitrateKbps = bitrateKbps
        self.resolution = resolution
        super.init()
    }

    func connect(session: RemoteStreamSession, token: String, signaling: SessionSignalingService) async throws {
        self.session = session
        self.token = token
        self.signaling = signaling

        let configuration = RTCConfiguration()
        configuration.iceServers = []
        configuration.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
        )
        guard let peer = Self.factory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: self
        ) else {
            throw URLError(.cannotCreateFile)
        }
        peerConnection = peer
        closed = false
        handshakeAcknowledged = false
        handshakeCompleted = false
        didSendInputMetadata = false
        configureAudioPlayback()
        createChannels(on: peer)
        addReceiveTransceivers(to: peer)

        let offerConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                kRTCMediaConstraintsOfferToReceiveAudio: kRTCMediaConstraintsValueTrue,
                kRTCMediaConstraintsOfferToReceiveVideo: kRTCMediaConstraintsValueTrue
            ],
            optionalConstraints: nil
        )
        let offer = try await createOffer(on: peer, constraints: offerConstraints)
        let localSDP = preferH264AndSetBitrate(offer.sdp, bitrateKbps: bitrateKbps)
        let localDescription = RTCSessionDescription(type: .offer, sdp: localSDP)
        try await setLocalDescription(localDescription, on: peer)
        let gatheredCandidates = await waitForLocalCandidates(on: peer)

        let answer = try await signaling.exchangeSDP(localSDP, session: session, token: token)
        try await setRemoteDescription(
            RTCSessionDescription(type: .answer, sdp: answer),
            on: peer
        )

        let candidatePayload = gatheredCandidates.map { candidate in
            var value: [String: Any] = [
                "candidate": candidate.sdp,
                "sdpMLineIndex": Int(candidate.sdpMLineIndex)
            ]
            if let mid = candidate.sdpMid {
                value["sdpMid"] = mid
            }
            return value
        }
        let remoteCandidateValues = try await signaling.exchangeICE(
            candidatePayload,
            session: session,
            token: token
        )
        for value in remoteCandidateValues {
            guard let candidateText = value["candidate"] as? String,
                  candidateText != "a=end-of-candidates" else {
                continue
            }
            let mid = value["sdpMid"] as? String
            let line = (value["sdpMLineIndex"] as? NSNumber)?.int32Value ?? 0
            for candidate in remoteCandidates(
                candidateText: candidateText,
                line: line,
                mid: mid
            ) {
                try await add(candidate, to: peer)
            }
        }

        startInputPolling()
        startStatsPolling()
    }

    func close() {
        closed = true
        reconnectTask?.cancel()
        reconnectTask = nil
        inputTimer?.invalidate()
        inputTimer = nil
        statsTimer?.invalidate()
        statsTimer = nil
        channels.values.forEach { $0.close() }
        channels.removeAll()
        peerConnection?.close()
        peerConnection = nil
        videoTrack = nil
        isInputReady = false
        didSendInputMetadata = false
        connectionState = "Disconnected"
    }

    private func createChannels(on peer: RTCPeerConnection) {
        let channelDefinitions = [
            ("input", "1.0"),
            ("control", "controlV1"),
            ("message", "messageV1"),
            ("chat", "chatV1")
        ]
        for (label, protocolName) in channelDefinitions {
            let configuration = RTCDataChannelConfiguration()
            configuration.isOrdered = true
            configuration.protocol = protocolName
            if let channel = peer.dataChannel(forLabel: label, configuration: configuration) {
                channel.delegate = self
                channels[label] = channel
            }
        }
    }

    private func addReceiveTransceivers(to peer: RTCPeerConnection) {
        let audio = RTCRtpTransceiverInit()
        audio.direction = .sendRecv
        _ = peer.addTransceiver(of: .audio, init: audio)

        let video = RTCRtpTransceiverInit()
        video.direction = .recvOnly
        _ = peer.addTransceiver(of: .video, init: video)
    }

    private func configureAudioPlayback() {
        let audioSession = RTCAudioSession.sharedInstance()
        audioSession.lockForConfiguration()
        do {
            try audioSession.setCategory(AVAudioSession.Category.playback)
            try audioSession.setMode(AVAudioSession.Mode.default)
            try audioSession.setActive(true)
        } catch {
            DispatchQueue.main.async {
                self.connectionState = "Audio setup failed: \(error.localizedDescription)"
            }
        }
        audioSession.unlockForConfiguration()
    }

    private func createOffer(
        on peer: RTCPeerConnection,
        constraints: RTCMediaConstraints
    ) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RTCSessionDescription, Error>) in
            peer.offer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    continuation.resume(returning: description)
                } else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                }
            }
        }
    }

    private func setLocalDescription(_ description: RTCSessionDescription, on peer: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func setRemoteDescription(_ description: RTCSessionDescription, on peer: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func add(_ candidate: RTCIceCandidate, to peer: RTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.add(candidate) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func remoteCandidates(candidateText: String, line: Int32, mid: String?) -> [RTCIceCandidate] {
        let candidateLine = candidateText.hasPrefix("a=") ? String(candidateText.dropFirst(2)) : candidateText
        let fields = candidateLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count > 6, fields[4].hasPrefix("2001:"),
              let teredo = Self.decodeTeredoAddress(fields[4]) else {
            return [RTCIceCandidate(sdp: candidateText, sdpMLineIndex: line, sdpMid: mid)]
        }

        let addressCandidates = [
            "a=candidate:10 1 UDP 1 \(teredo.address) 9002 typ host ",
            "a=candidate:11 1 UDP 1 \(teredo.address) \(teredo.port) typ host "
        ]
        return addressCandidates.map {
            RTCIceCandidate(sdp: $0, sdpMLineIndex: line, sdpMid: mid)
        } + [RTCIceCandidate(sdp: candidateText, sdpMLineIndex: line, sdpMid: mid)]
    }

    private static func decodeTeredoAddress(_ address: String) -> (address: String, port: UInt16)? {
        let groups = address.split(separator: ":")
        guard groups.count == 8,
              let encodedPort = UInt16(String(groups[5]), radix: 16),
              groups[6].count == 4,
              groups[7].count == 4 else {
            return nil
        }
        let clientAddress = String(groups[6]) + String(groups[7])
        var octets: [UInt16] = []
        for offset in stride(from: 0, to: clientAddress.count, by: 2) {
            let start = clientAddress.index(clientAddress.startIndex, offsetBy: offset)
            let end = clientAddress.index(start, offsetBy: 2)
            guard let value = UInt16(String(clientAddress[start..<end]), radix: 16) else {
                return nil
            }
            octets.append(value ^ 0xFF)
        }
        guard octets.count == 4 else { return nil }
        return (
            octets.map { String($0) }.joined(separator: "."),
            encodedPort ^ 0xFFFF
        )
    }

    private func waitForLocalCandidates(on peer: RTCPeerConnection) async -> [RTCIceCandidate] {
        if peer.iceGatheringState == .complete {
            return localCandidates
        }
        return await withCheckedContinuation { continuation in
            candidateWaiter = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, let waiter = self.candidateWaiter else { return }
                self.candidateWaiter = nil
                waiter.resume(returning: self.localCandidates)
            }
        }
    }

    private func startInputPolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.closed else { return }
            self.inputTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                guard let self, !self.closed, let channel = self.channels["input"],
                      channel.readyState == .open else {
                    return
                }
                let timestamp = ProcessInfo.processInfo.systemUptime * 1000
                let packet = InputPacketEncoder.gamepad(
                    sequence: self.sequence,
                    timestampMilliseconds: timestamp,
                    state: self.input.snapshot()
                )
                self.sequence &+= 1
                channel.sendData(RTCDataBuffer(data: packet, isBinary: true))
            }
            RunLoop.main.add(timer, forMode: .common)
            self.inputTimer = timer
        }
    }

    private func startStatsPolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.closed else { return }
            self.statsTimer?.invalidate()
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.readStatistics()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.statsTimer = timer
        }
    }

    private func readStatistics() {
        peerConnection?.statistics { [weak self] report in
            var roundTripTime: Double?
            var fps: Int?
            for statistic in report.statistics.values {
                if statistic.type == "candidate-pair",
                   let current = statistic.values["currentRoundTripTime"] as? NSNumber {
                    roundTripTime = current.doubleValue
                }
                if statistic.type == "inbound-rtp",
                   let kind = statistic.values["kind"] as? String,
                   kind == "video",
                   let currentFPS = statistic.values["framesPerSecond"] as? NSNumber {
                    fps = currentFPS.intValue
                }
            }
            DispatchQueue.main.async {
                if let roundTripTime {
                    self?.latencyMilliseconds = Int((roundTripTime * 1000).rounded())
                }
                self?.framesPerSecond = fps
            }
        }
    }

    private func sendJSON(_ object: [String: Any], on channelName: String) {
        guard let channel = channels[channelName], channel.readyState == .open else {
            return
        }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: object)
        } catch {
            DispatchQueue.main.async {
                self.connectionState = "Unable to encode a stream control message: \(error.localizedDescription)"
            }
            return
        }
        channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    private func sendMessageHandshake() {
        guard !handshakeAcknowledged else { return }
        sendJSON([
            "type": "Handshake",
            "version": "messageV1",
            "id": "be0bfc6d-1e83-4c8a-90ed-fa8601c5a179",
            "cv": "0"
        ], on: "message")
    }

    private func handleMessage(_ data: Data) {
        let object: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                connectionState = "Xbox sent an unrecognized message-channel response."
                return
            }
            object = decoded
        } catch {
            connectionState = "Xbox sent an invalid message-channel response: \(error.localizedDescription)"
            return
        }
        guard let type = object["type"] as? String else {
            return
        }
        guard type == "HandshakeAck" else { return }
        handshakeAcknowledged = true
        completeHandshakeIfReady()
    }

    private func completeHandshakeIfReady() {
        guard handshakeAcknowledged, !handshakeCompleted,
              channels["control"]?.readyState == .open,
              channels["input"]?.readyState == .open,
              channels["message"]?.readyState == .open else {
            return
        }
        handshakeCompleted = true
        sendJSON([
            "message": "authorizationRequest",
            "accessKey": "4BDB3609-C1F1-4195-9B37-FEFF45DA8B8E"
        ], on: "control")
        sendJSON(["message": "gamepadChanged", "gamepadIndex": 0, "wasAdded": true], on: "control")
        sendJSON(["message": "gamepadChanged", "gamepadIndex": 0, "wasAdded": false], on: "control")
        sendInputMetadataIfNeeded()
        sendMessageConfiguration()
        DispatchQueue.main.async { self.isInputReady = true }
    }

    private func sendInputMetadataIfNeeded() {
        guard !didSendInputMetadata, let inputChannel = channels["input"],
              inputChannel.readyState == .open else {
            return
        }
        didSendInputMetadata = true
        inputChannel.sendData(RTCDataBuffer(data: InputPacketEncoder.metadata(), isBinary: true))
    }

    private func sendMessageConfiguration() {
        let messages: [(String, [String: Any])] = [
            ("/streaming/systemUi/configuration", ["version": [0, 2, 0], "systemUis": []]),
            ("/streaming/properties/clientappinstallidchanged", ["clientAppInstallId": "c97d7ee0-73b2-4239-bf1d-9d805a338429"]),
            ("/streaming/characteristics/orientationchanged", ["orientation": 0]),
            ("/streaming/characteristics/touchinputenabledchanged", ["touchInputEnabled": true]),
            ("/streaming/characteristics/clientdevicecapabilities", [:]),
            ("/streaming/characteristics/dimensionschanged", [
                "horizontal": resolution >= 1080 ? 1920 : 1280,
                "vertical": resolution >= 1080 ? 1080 : 720,
                "preferredWidth": resolution >= 1080 ? 1920 : 1280,
                "preferredHeight": resolution >= 1080 ? 1080 : 720,
                "safeAreaLeft": 0,
                "safeAreaTop": 0,
                "safeAreaRight": resolution >= 1080 ? 1920 : 1280,
                "safeAreaBottom": resolution >= 1080 ? 1080 : 720,
                "supportsCustomResolution": true
            ])
        ]
        for (target, content) in messages {
            do {
                let serializedContent = try JSONSerialization.data(withJSONObject: content)
                guard let contentString = String(data: serializedContent, encoding: .utf8) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                sendJSON([
                    "type": "Message",
                    "content": contentString,
                    "id": UUID().uuidString,
                    "target": target,
                    "cv": ""
                ], on: "message")
            } catch {
                connectionState = "Unable to encode stream configuration: \(error.localizedDescription)"
                return
            }
        }
    }

    private func preferH264AndSetBitrate(_ source: String, bitrateKbps: Int) -> String {
        var lines = source.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let videoIndex = lines.firstIndex(where: { $0.hasPrefix("m=video ") }) else {
            return source
        }
        let mediaParts = lines[videoIndex].split(separator: " ").map(String.init)
        if mediaParts.count > 3 {
            let h264Payloads = lines.compactMap { line -> String? in
                guard line.hasPrefix("a=rtpmap:"),
                      line.lowercased().contains("h264/") else {
                    return nil
                }
                return line.dropFirst("a=rtpmap:".count).split(separator: " ").first.map(String.init)
            }
            let videoPayloads = Array(mediaParts.dropFirst(3))
            let preferred = h264Payloads.filter { videoPayloads.contains($0) }
            let ordered = preferred + videoPayloads.filter { !preferred.contains($0) }
            lines[videoIndex] = (Array(mediaParts.prefix(3)) + ordered).joined(separator: " ")
        }
        var insertionIndex = videoIndex + 1
        while insertionIndex < lines.count,
              lines[insertionIndex].hasPrefix("i=") || lines[insertionIndex].hasPrefix("c=") {
            insertionIndex += 1
        }
        if insertionIndex < lines.count, lines[insertionIndex].hasPrefix("b=AS:") {
            lines[insertionIndex] = "b=AS:\(max(500, bitrateKbps))"
        } else {
            lines.insert("b=AS:\(max(500, bitrateKbps))", at: insertionIndex)
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func scheduleReconnect() {
        guard !closed, reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            if !self.closed,
               (self.peerConnection?.iceConnectionState == .failed ||
                self.peerConnection?.iceConnectionState == .disconnected) {
                self.onReconnectRequested?()
            }
            self.reconnectTask = nil
        }
    }
}

extension WebRTCTransport: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        DispatchQueue.main.async {
            self.videoTrack = stream.videoTracks.first
            stream.audioTracks.forEach { $0.isEnabled = true }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        DispatchQueue.main.async { self.videoTrack = nil }
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        DispatchQueue.main.async {
            switch newState {
            case .connected, .completed:
                self.connectionState = "Connected"
            case .checking:
                self.connectionState = "Connecting"
            case .disconnected:
                self.connectionState = "Reconnecting"
                self.scheduleReconnect()
            case .failed:
                self.connectionState = "Connection failed"
                self.scheduleReconnect()
            case .closed:
                self.connectionState = "Disconnected"
            case .new:
                self.connectionState = "Preparing"
            @unknown default:
                self.connectionState = "Unknown"
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        guard newState == .complete else { return }
        DispatchQueue.main.async {
            guard let waiter = self.candidateWaiter else { return }
            self.candidateWaiter = nil
            waiter.resume(returning: self.localCandidates)
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        DispatchQueue.main.async { self.localCandidates.append(candidate) }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        DispatchQueue.main.async {
            dataChannel.delegate = self
            self.channels[dataChannel.label] = dataChannel
        }
    }
}

extension WebRTCTransport: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        DispatchQueue.main.async {
            guard dataChannel.readyState == .open else { return }
            if dataChannel.label == "message" {
                self.sendMessageHandshake()
            }
            self.completeHandshakeIfReady()
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if dataChannel.label == "message" {
            DispatchQueue.main.async { self.handleMessage(buffer.data) }
        }
    }
}
