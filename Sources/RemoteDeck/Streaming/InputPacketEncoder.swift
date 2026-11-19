import Foundation

struct ControllerState: Equatable {
    var nexus = false
    var menu = false
    var view = false
    var a = false
    var b = false
    var x = false
    var y = false
    var dpadUp = false
    var dpadDown = false
    var dpadLeft = false
    var dpadRight = false
    var leftShoulder = false
    var rightShoulder = false
    var leftThumb = false
    var rightThumb = false
    var leftThumbX = 0.0
    var leftThumbY = 0.0
    var rightThumbX = 0.0
    var rightThumbY = 0.0
    var leftTrigger = 0.0
    var rightTrigger = 0.0
}

enum InputPacketEncoder {
    static func metadata(maxTouchPoints: UInt8 = 1, sequence: UInt32 = 0, timestampMilliseconds: Double = 0) -> Data {
        var data = Data()
        append(UInt16(8), littleEndianTo: &data)
        append(sequence, littleEndianTo: &data)
        append(timestampMilliseconds, littleEndianTo: &data)
        data.append(maxTouchPoints)
        return data
    }

    static func gamepad(sequence: UInt32, timestampMilliseconds: Double, state: ControllerState) -> Data {
        var data = Data()
        append(UInt16(2), littleEndianTo: &data)
        append(sequence, littleEndianTo: &data)
        append(timestampMilliseconds, littleEndianTo: &data)
        data.append(1)
        data.append(0)
        append(buttonMask(state), littleEndianTo: &data)
        append(axis(state.leftThumbX), littleEndianTo: &data)
        append(axis(-state.leftThumbY), littleEndianTo: &data)
        append(axis(state.rightThumbX), littleEndianTo: &data)
        append(axis(-state.rightThumbY), littleEndianTo: &data)
        append(trigger(state.leftTrigger), littleEndianTo: &data)
        append(trigger(state.rightTrigger), littleEndianTo: &data)
        append(UInt32(1), littleEndianTo: &data)
        append(UInt32(1), bigEndianTo: &data)
        return data
    }

    private static func buttonMask(_ state: ControllerState) -> UInt16 {
        var mask: UInt16 = 0
        if state.nexus { mask |= 2 }
        if state.menu { mask |= 4 }
        if state.view { mask |= 8 }
        if state.a { mask |= 16 }
        if state.b { mask |= 32 }
        if state.x { mask |= 64 }
        if state.y { mask |= 128 }
        if state.dpadUp { mask |= 256 }
        if state.dpadDown { mask |= 512 }
        if state.dpadLeft { mask |= 1024 }
        if state.dpadRight { mask |= 2048 }
        if state.leftShoulder { mask |= 4096 }
        if state.rightShoulder { mask |= 8192 }
        if state.leftThumb { mask |= 16384 }
        if state.rightThumb { mask |= 32768 }
        return mask
    }

    private static func axis(_ value: Double) -> Int16 {
        let scaled = Int((min(1, max(-1, value)) * 32767).rounded())
        return Int16(min(32767, max(-32767, scaled)))
    }

    private static func trigger(_ value: Double) -> UInt16 {
        UInt16((min(1, max(0, value)) * 65535).rounded())
    }

    private static func append<T: FixedWidthInteger>(_ value: T, littleEndianTo data: inout Data) {
        var encoded = value.littleEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }

    private static func append<T: FixedWidthInteger>(_ value: T, bigEndianTo data: inout Data) {
        var encoded = value.bigEndian
        withUnsafeBytes(of: &encoded) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: Double, littleEndianTo data: inout Data) {
        append(value.bitPattern, littleEndianTo: &data)
    }
}
