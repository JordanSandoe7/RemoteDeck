import SwiftUI
import WebRTC

struct PlayerView: View {
    @EnvironmentObject private var model: RemoteDeckModel
    @ObservedObject var transport: WebRTCTransport
    @State private var controlsVisible = true

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let track = transport.videoTrack {
                    WebRTCVideoSurface(track: track)
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        ProgressView().tint(.green)
                        Text(transport.connectionState)
                            .foregroundStyle(.white)
                    }
                }
                if !controlsVisible {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
                        }
                }
                VStack {
                    topBar
                    Spacer()
                    if model.showTouchControls && controlsVisible {
                        TouchControllerView(controller: model.controller)
                            .frame(height: min(geometry.size.height * 0.72, 300))
                            .padding(.horizontal, 22)
                            .padding(.bottom, 18)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 12)
            }
        }
        .background(Color.black)
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await model.disconnect() }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.55), in: Circle())
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selectedConsole?.deviceName ?? "Xbox")
                    .font(.headline)
                HStack(spacing: 10) {
                    Text(transport.connectionState)
                    if let latency = transport.latencyMilliseconds {
                        Text("\(latency) ms")
                    }
                    if let fps = transport.framesPerSecond {
                        Text("\(fps) fps")
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { controlsVisible.toggle() }
            } label: {
                Image(systemName: controlsVisible ? "eye.slash" : "eye")
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.55), in: Circle())
            }
            if transport.isInputReady {
                Image(systemName: model.controller.controllerName == nil ? "hand.tap" : "gamecontroller.fill")
                    .foregroundStyle(.green)
                    .padding(10)
                    .background(.black.opacity(0.55), in: Circle())
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct WebRTCVideoSurface: UIViewRepresentable {
    let track: RTCVideoTrack

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = .scaleAspectFit
        return view
    }

    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        if context.coordinator.track !== track {
            if let oldTrack = context.coordinator.track {
                oldTrack.remove(view)
            }
            track.add(view)
            context.coordinator.track = track
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var track: RTCVideoTrack?
    }
}

private struct TouchControllerView: View {
    @ObservedObject var controller: GameControllerInput

    var body: some View {
        HStack(alignment: .bottom) {
            TouchStick(controller: controller, rightStick: false)
            TouchDPad(controller: controller)
            Spacer(minLength: 10)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TouchButton(title: "LB", compact: true) { set(\.leftShoulder, on: $0) }
                    TouchButton(title: "RB", compact: true) { set(\.rightShoulder, on: $0) }
                }
                HStack(spacing: 8) {
                    TouchButton(title: "LT", compact: true) { pressed in
                        controller.updateTouch { $0.leftTrigger = pressed ? 1 : 0 }
                    }
                    TouchButton(title: "RT", compact: true) { pressed in
                        controller.updateTouch { $0.rightTrigger = pressed ? 1 : 0 }
                    }
                }
                HStack(spacing: 8) {
                    TouchButton(title: "Y") { set(\.y, on: $0) }
                    TouchButton(title: "X") { set(\.x, on: $0) }
                }
                HStack(spacing: 8) {
                    TouchButton(title: "B") { set(\.b, on: $0) }
                    TouchButton(title: "A") { set(\.a, on: $0) }
                }
                HStack(spacing: 6) {
                    TouchButton(title: "Xbox", compact: true) { set(\.nexus, on: $0) }
                    TouchButton(title: "View", compact: true) { set(\.view, on: $0) }
                    TouchButton(title: "Menu", compact: true) { set(\.menu, on: $0) }
                }
            }
            Spacer(minLength: 10)
            TouchStick(controller: controller, rightStick: true)
        }
    }

    private func set(_ keyPath: WritableKeyPath<ControllerState, Bool>, on pressed: Bool) {
        controller.updateTouch { $0[keyPath: keyPath] = pressed }
    }
}

private struct TouchDPad: View {
    @ObservedObject var controller: GameControllerInput

    var body: some View {
        VStack(spacing: 2) {
            button("↑", keyPath: \.dpadUp)
            HStack(spacing: 2) {
                button("←", keyPath: \.dpadLeft)
                button("↓", keyPath: \.dpadDown)
                button("→", keyPath: \.dpadRight)
            }
        }
        .accessibilityLabel("D-pad")
    }

    private func button(_ title: String, keyPath: WritableKeyPath<ControllerState, Bool>) -> some View {
        TouchButton(title: title, compact: true) { pressed in
            controller.updateTouch { $0[keyPath: keyPath] = pressed }
        }
    }
}

private struct TouchStick: View {
    @ObservedObject var controller: GameControllerInput
    let rightStick: Bool
    @State private var offset = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(min(geometry.size.width, geometry.size.height), 150)
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 1))
                Circle()
                    .fill(.white.opacity(0.38))
                    .frame(width: diameter * 0.4, height: diameter * 0.4)
                    .offset(offset)
            }
            .frame(width: diameter, height: diameter)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let limit = diameter * 0.28
                        let x = min(limit, max(-limit, value.translation.width))
                        let y = min(limit, max(-limit, value.translation.height))
                        offset = CGSize(width: x, height: y)
                        setAxis(x: Double(x / limit), y: Double(-y / limit))
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.65)) {
                            offset = .zero
                        }
                        setAxis(x: 0, y: 0)
                    }
            )
        }
        .frame(width: 150, height: 150)
        .accessibilityLabel(rightStick ? "Right thumbstick" : "Left thumbstick")
    }

    private func setAxis(x: Double, y: Double) {
        controller.updateTouch {
            if rightStick {
                $0.rightThumbX = x
                $0.rightThumbY = y
            } else {
                $0.leftThumbX = x
                $0.leftThumbY = y
            }
        }
    }
}

private struct TouchButton: View {
    let title: String
    var compact = false
    let action: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        Text(title)
            .font(.system(size: compact ? 11 : 17, weight: .bold, design: .rounded))
            .frame(width: compact ? 54 : 54, height: compact ? 34 : 54)
            .foregroundStyle(.white)
            .background(pressed ? .green.opacity(0.8) : .white.opacity(0.24), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 1))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        action(true)
                    }
                    .onEnded { _ in
                        pressed = false
                        action(false)
                    }
            )
    }
}
