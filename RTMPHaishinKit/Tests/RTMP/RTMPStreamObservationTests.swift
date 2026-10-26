import AVFoundation
import Foundation
import Testing

@testable import RTMPHaishinKit

private final class VideoOutputObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(CMTime, TimeInterval)] = []

    func record(_ time: CMTime, _ uptime: TimeInterval) {
        lock.withLock { values.append((time, uptime)) }
    }

    var snapshot: [(CMTime, TimeInterval)] { lock.withLock { values } }
}

@Suite struct RTMPStreamObservationTests {
    @Test func firstVideoOutputIsOptInAndResettable() async throws {
        let connection = RTMPConnection()
        let stream = RTMPStream(connection: connection)
        let observations = VideoOutputObservations()
        let first = try makeSample(seconds: 1)
        await stream.append(first)
        #expect(observations.snapshot.isEmpty)

        await stream.setFirstVideoOutputObserver(observations.record)
        let before = ProcessInfo.processInfo.systemUptime
        await stream.append(try makeSample(seconds: 2, codec: kCMVideoCodecType_JPEG))
        #expect(observations.snapshot.isEmpty)
        await stream.append(try makeSample(seconds: 3))
        await stream.append(try makeSample(seconds: 4))
        let initial = observations.snapshot
        #expect(initial.count == 1)
        #expect(initial.first?.0.seconds == 3)
        #expect(initial.first.map { $0.1 >= before && $0.1 <= ProcessInfo.processInfo.systemUptime } == true)

        await stream.setFirstVideoOutputObserver(observations.record)
        await stream.append(try makeSample(seconds: 5))
        await stream.append(try makeSample(seconds: 6))
        #expect(observations.snapshot.map { $0.0.seconds } == [3, 5])

        await stream.setFirstVideoOutputObserver(observations.record)
        await stream.setFirstVideoOutputObserver(nil)
        await stream.append(try makeSample(seconds: 7))
        #expect(observations.snapshot.count == 2)
    }

    private func makeSample(seconds: Double, codec: CMVideoCodecType = kCMVideoCodecType_H264) throws -> CMSampleBuffer {
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codec,
            width: 16,
            height: 16,
            extensions: nil,
            formatDescriptionOut: &format
        ) == noErr)
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: 6,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: 6,
            flags: 0,
            blockBufferOut: &block
        ) == noErr)
        let data = Data([0, 0, 0, 2, 0x65, 0x80])
        let dataBuffer = try #require(block)
        #expect(data.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: dataBuffer, offsetIntoDestination: 0, dataLength: data.count)
        } == noErr)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
            decodeTimeStamp: .invalid
        )
        var size = data.count
        var sample: CMSampleBuffer?
        let formatDescription = try #require(format)
        #expect(CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: dataBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sample
        ) == noErr)
        return try #require(sample)
    }
}
