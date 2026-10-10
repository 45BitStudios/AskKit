import AVFoundation
import XCTest
@testable import AskKit

final class AskVoiceLevelTests: XCTestCase {
    func testSilenceIsQuiet() {
        let samples: [Float] = [0, 0, 0, 0]
        samples.withUnsafeBufferPointer { buffer in
            XCTAssertEqual(AskVoiceLevel.normalized(samples: buffer), 0, accuracy: 0.0001)
        }
    }

    func testQuietSpeechStillRises() {
        let samples = Array(repeating: Float(0.01), count: 32)
        samples.withUnsafeBufferPointer { buffer in
            XCTAssertEqual(AskVoiceLevel.normalized(samples: buffer), 0.374, accuracy: 0.01)
        }
    }

    func testLoudSpeechReachesFullScale() {
        let samples = Array(repeating: Float(0.5), count: 16)
        samples.withUnsafeBufferPointer { buffer in
            XCTAssertEqual(AskVoiceLevel.normalized(samples: buffer), 1, accuracy: 0.0001)
        }
    }

    func testEmptySamplesStayQuiet() {
        let samples: [Float] = []
        samples.withUnsafeBufferPointer { buffer in
            XCTAssertEqual(AskVoiceLevel.normalized(samples: buffer), 0)
        }
    }

    func testSmoothAttacksFasterThanItReleases() {
        let risen = AskVoiceLevel.smooth(previous: 0, sample: 1)
        XCTAssertEqual(risen, 0.55, accuracy: 0.0001)
        let fallen = AskVoiceLevel.smooth(previous: 1, sample: 0)
        XCTAssertEqual(fallen, 0.78, accuracy: 0.0001)
    }

    func testSmoothClimbsTowardTheSample() {
        var level = 0.0
        for _ in 0..<24 {
            level = AskVoiceLevel.smooth(previous: level, sample: 1)
            XCTAssertGreaterThanOrEqual(level, 0)
            XCTAssertLessThanOrEqual(level, 1)
        }
        XCTAssertGreaterThan(level, 0.95)
    }

    func testMeterRisesAndResets() {
        let meter = AskVoiceMeter()
        XCTAssertEqual(meter.read(), 0)
        meter.push(1)
        XCTAssertEqual(meter.read(), 0.55, accuracy: 0.0001)
        meter.push(-2)
        XCTAssertLessThan(meter.read(), 0.55)
        meter.reset()
        XCTAssertEqual(meter.read(), 0)
    }

    func testFloatBufferReadsTheFirstChannel() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8))
        buffer.frameLength = 8
        fill(buffer, float: 0)
        XCTAssertEqual(AskVoiceLevel.normalized(AVReadOnlyAudioPCMBuffer(copying: buffer)), 0, accuracy: 0.0001)
        fill(buffer, float: 0.5)
        XCTAssertEqual(AskVoiceLevel.normalized(AVReadOnlyAudioPCMBuffer(copying: buffer)), 1, accuracy: 0.0001)
    }

    func testEmptyBufferStaysQuiet() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8))
        buffer.frameLength = 0
        XCTAssertEqual(AskVoiceLevel.normalized(AVReadOnlyAudioPCMBuffer(copying: buffer)), 0)
    }

    func testInt16BufferUsesTheSameCurve() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4
        switch buffer.mutableChannelData(0) {
        case .int16(var samples):
            for index in 0..<min(4, samples.count) {
                samples[index] = Int16.max
            }
        case .float(let samples):
            XCTFail("Expected int16 channel data, got \(samples.count) float frames")
        case .int32(let samples):
            XCTFail("Expected int16 channel data, got \(samples.count) int32 frames")
        @unknown default:
            XCTFail("Expected int16 channel data")
        }
        XCTAssertEqual(AskVoiceLevel.normalized(AVReadOnlyAudioPCMBuffer(copying: buffer)), 1, accuracy: 0.0001)
    }

    private func fill(_ buffer: AVAudioPCMBuffer, float value: Float) {
        switch buffer.mutableChannelData(0) {
        case .float(var samples):
            let count = min(Int(buffer.frameLength), samples.count)
            for index in 0..<count {
                samples[index] = value
            }
        case .int16(let samples):
            XCTFail("Expected float channel data, got \(samples.count) int16 frames")
        case .int32(let samples):
            XCTFail("Expected float channel data, got \(samples.count) int32 frames")
        @unknown default:
            XCTFail("Expected float channel data")
        }
    }
}
