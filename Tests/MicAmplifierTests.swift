#if os(iOS)
import XCTest
@testable import MicAmplifier

final class MicAmplifierTests: XCTestCase {

    func testInitialState() {
        let amp = MicAmplifier()
        XCTAssertEqual(amp.state, .stopped)
    }

    func testInitialGain() {
        let amp = MicAmplifier(initialGainDB: 12.0)
        XCTAssertEqual(amp.gainDB, 12.0, accuracy: 0.001)
    }

    func testGainClampsToUpperBound() {
        let amp = MicAmplifier()
        amp.gainDB = 100.0
        XCTAssertEqual(amp.gainDB, 24.0, accuracy: 0.001)
    }

    func testGainClampsToLowerBound() {
        let amp = MicAmplifier()
        amp.gainDB = -200.0
        XCTAssertEqual(amp.gainDB, -96.0, accuracy: 0.001)
    }

    func testLinearGainUnityIsZeroDB() {
        let amp = MicAmplifier()
        amp.linearGain = 1.0
        XCTAssertEqual(amp.gainDB, 0.0, accuracy: 0.001)
    }

    func testLinearGainDoubleIsSixDB() {
        let amp = MicAmplifier()
        amp.linearGain = 2.0
        XCTAssertEqual(amp.gainDB, 6.0206, accuracy: 0.01)
    }

    func testLinearGainRoundTrip() {
        let amp = MicAmplifier()
        amp.gainDB = 10.0
        XCTAssertEqual(amp.linearGain, pow(10.0, 0.5), accuracy: 0.001)
    }

    func testLinearGainZeroClampsToFloor() {
        let amp = MicAmplifier()
        amp.linearGain = 0.0
        XCTAssertEqual(amp.gainDB, -96.0, accuracy: 0.001)
    }

    func testStopFromStoppedStaysStopped() {
        let amp = MicAmplifier()
        amp.stop()
        XCTAssertEqual(amp.state, .stopped)
    }
}
#endif
