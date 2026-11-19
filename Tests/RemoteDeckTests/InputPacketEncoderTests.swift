import Foundation
import XCTest
@testable import RemoteDeck

final class InputPacketEncoderTests: XCTestCase {
    func testClientMetadataEncodesReportTypeAndTouchpointCount() {
        let packet = InputPacketEncoder.metadata(
            maxTouchPoints: 2,
            sequence: 0x12345678,
            timestampMilliseconds: 10
        )

        XCTAssertEqual(packet.count, 15)
        XCTAssertEqual(readUInt16(packet, at: 0), 8)
        XCTAssertEqual(readUInt32(packet, at: 2), 0x12345678)
        XCTAssertEqual(packet[14], 2)
    }

    func testGamepadPacketEncodesButtonsAxesTriggersAndPhysicality() {
        var state = ControllerState()
        state.a = true
        state.dpadRight = true
        state.leftThumbX = 1
        state.leftThumbY = 1
        state.rightThumbX = -1
        state.leftTrigger = 0.5
        state.rightTrigger = 1

        let packet = InputPacketEncoder.gamepad(
            sequence: 7,
            timestampMilliseconds: 123.5,
            state: state
        )

        XCTAssertEqual(packet.count, 38)
        XCTAssertEqual(readUInt16(packet, at: 0), 2)
        XCTAssertEqual(readUInt32(packet, at: 2), 7)
        XCTAssertEqual(packet[14], 1)
        XCTAssertEqual(packet[15], 0)
        XCTAssertEqual(readUInt16(packet, at: 16), 16 | 2048)
        XCTAssertEqual(readInt16(packet, at: 18), 32767)
        XCTAssertEqual(readInt16(packet, at: 20), -32767)
        XCTAssertEqual(readInt16(packet, at: 22), -32767)
        XCTAssertEqual(readUInt16(packet, at: 26), 32768)
        XCTAssertEqual(readUInt16(packet, at: 28), 65535)
        XCTAssertEqual(readUInt32(packet, at: 30), 1)
        XCTAssertEqual(packet[34], 0)
        XCTAssertEqual(packet[35], 0)
        XCTAssertEqual(packet[36], 0)
        XCTAssertEqual(packet[37], 1)
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readInt16(_ data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(data, at: offset))
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
