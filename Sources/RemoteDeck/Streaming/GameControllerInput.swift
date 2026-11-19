import Combine
import Foundation
import GameController

final class GameControllerInput: ObservableObject {
    @Published private(set) var controllerName: String?
    @Published private(set) var touchState = ControllerState()

    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshControllerName() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshControllerName() }
        })
        refreshControllerName()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func updateTouch(_ update: (inout ControllerState) -> Void) {
        update(&touchState)
    }

    func snapshot() -> ControllerState {
        var physical = ControllerState()
        if let gamepad = GCController.controllers().first?.extendedGamepad {
            physical.a = gamepad.buttonA.isPressed
            physical.b = gamepad.buttonB.isPressed
            physical.x = gamepad.buttonX.isPressed
            physical.y = gamepad.buttonY.isPressed
            physical.leftShoulder = gamepad.leftShoulder.isPressed
            physical.rightShoulder = gamepad.rightShoulder.isPressed
            physical.leftTrigger = Double(gamepad.leftTrigger.value)
            physical.rightTrigger = Double(gamepad.rightTrigger.value)
            physical.leftThumbX = Double(gamepad.leftThumbstick.xAxis.value)
            physical.leftThumbY = Double(gamepad.leftThumbstick.yAxis.value)
            physical.rightThumbX = Double(gamepad.rightThumbstick.xAxis.value)
            physical.rightThumbY = Double(gamepad.rightThumbstick.yAxis.value)
            physical.dpadUp = gamepad.dpad.up.isPressed
            physical.dpadDown = gamepad.dpad.down.isPressed
            physical.dpadLeft = gamepad.dpad.left.isPressed
            physical.dpadRight = gamepad.dpad.right.isPressed
            physical.menu = gamepad.buttonMenu.isPressed
            physical.view = gamepad.buttonOptions?.isPressed ?? false
            physical.leftThumb = gamepad.leftThumbstickButton?.isPressed ?? false
            physical.rightThumb = gamepad.rightThumbstickButton?.isPressed ?? false
            if #available(iOS 14.0, *) {
                physical.nexus = gamepad.buttonHome?.isPressed ?? false
            }
        }

        var result = physical
        result.nexus = result.nexus || touchState.nexus
        result.menu = result.menu || touchState.menu
        result.view = result.view || touchState.view
        result.a = result.a || touchState.a
        result.b = result.b || touchState.b
        result.x = result.x || touchState.x
        result.y = result.y || touchState.y
        result.dpadUp = result.dpadUp || touchState.dpadUp
        result.dpadDown = result.dpadDown || touchState.dpadDown
        result.dpadLeft = result.dpadLeft || touchState.dpadLeft
        result.dpadRight = result.dpadRight || touchState.dpadRight
        result.leftShoulder = result.leftShoulder || touchState.leftShoulder
        result.rightShoulder = result.rightShoulder || touchState.rightShoulder
        result.leftThumb = result.leftThumb || touchState.leftThumb
        result.rightThumb = result.rightThumb || touchState.rightThumb
        if touchState.leftThumbX != 0 { result.leftThumbX = touchState.leftThumbX }
        if touchState.leftThumbY != 0 { result.leftThumbY = touchState.leftThumbY }
        if touchState.rightThumbX != 0 { result.rightThumbX = touchState.rightThumbX }
        if touchState.rightThumbY != 0 { result.rightThumbY = touchState.rightThumbY }
        if touchState.leftTrigger > 0 { result.leftTrigger = touchState.leftTrigger }
        if touchState.rightTrigger > 0 { result.rightTrigger = touchState.rightTrigger }
        return result
    }

    private func refreshControllerName() {
        controllerName = GCController.controllers().first?.vendorName
    }
}
