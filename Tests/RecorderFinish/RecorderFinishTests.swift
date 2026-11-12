import AVFoundation

public protocol StreamOutput {}
public protocol StreamConvertible {}
public protocol MediaMixerOutput {}
public final class MediaMixer {}

final class FirstAppendObservations: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(Double, TimeInterval)] = []

    func record(_ time: CMTime, _ uptime: TimeInterval) {
        lock.withLock { values.append((time.seconds, uptime)) }
    }

    var snapshot: [(Double, TimeInterval)] { lock.withLock { values } }
}

@main struct RecorderFinishTests {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        var failures = 0
        let cases: [(String, AVAssetWriter.Status, AVAssetWriter.Status, Bool)] = [
            ("completed", .writing, .completed, false),
            ("failed-at-finish", .writing, .failed, true),
            ("cancelled-at-finish", .writing, .cancelled, true),
            ("unknown-at-finish", .writing, .unknown, true),
            ("still-writing-at-finish", .writing, .writing, true),
            ("already-failed", .failed, .failed, true)
        ]
        for (name, initial, final, shouldThrow) in cases {
            AVAssetWriter.nextInitialStatus = initial
            AVAssetWriter.nextFinalStatus = final
            let recorder = StreamRecorder()
            let url = root.appendingPathComponent("actual-source-" + name + ".mp4")
            try await recorder.startRecording(url)
            var threw = false
            do {
                let result = try await recorder.stopRecording()
                precondition(result == url)
            } catch StreamRecorder.Error.failedToFinishWriting(let error) {
                threw = true
                if initial == .failed || final == .failed {
                    precondition((error as NSError?)?.domain == "FixtureWriter")
                }
            }
            let outputURL = await recorder.outputURL
            let isRecording = await recorder.isRecording
            let cleared = outputURL == nil && !isRecording
            precondition(cleared)
            let matches = threw == shouldThrow
            if !matches { failures += 1 }
            print("\(name): threw=\(threw) expected=\(shouldThrow) cleanup=\(cleared) \(matches ? "PASS" : "FAIL")")
        }
        let observations = FirstAppendObservations()
        let recorder = StreamRecorder(onFirstVideoAppend: observations.record)
        AVAssetWriter.nextInitialStatus = .unknown
        AVAssetWriter.nextFinalStatus = .completed
        try await recorder.startRecording(
            root.appendingPathComponent("first-append.mp4"),
            settings: [.video: StreamRecorder.defaultSettings[.video]!]
        )
        let before = ProcessInfo.processInfo.systemUptime
        AVAssetWriterInput.appendResult = false
        await append(.video, seconds: 1, to: recorder)
        precondition(observations.snapshot.isEmpty, "failed append must not emit")
        AVAssetWriterInput.appendResult = true
        await append(.video, seconds: 2, to: recorder)
        await append(.video, seconds: 3, to: recorder)
        let first = observations.snapshot
        precondition(first.count == 1, "first successful video append must emit once")
        precondition(first[0].0 == 2)
        precondition(first[0].1 >= before && first[0].1 <= ProcessInfo.processInfo.systemUptime)
        _ = try await recorder.stopRecording()
        try await recorder.startRecording(
            root.appendingPathComponent("reused-recorder.mp4"),
            settings: [.video: StreamRecorder.defaultSettings[.video]!]
        )
        await append(.video, seconds: 4, to: recorder)
        precondition(observations.snapshot.count == 1, "observer is once per recorder instance")
        _ = try await recorder.stopRecording()
        print("first successful video append: once, successful frame PTS, transition uptime PASS")
        failures += try await checkWriterFailure(root)
        print("actual-source recorder contract failures: \(failures)")
        if failures > 0 { exit(1) }
    }

    private static func checkWriterFailure(_ root: URL) async throws -> Int {
        var failures = 0
        for mediaType in [AVMediaType.audio, .video] {
            let recorder = StreamRecorder()
            // Reusing the recorder also checks that the failure latch resets.
            for (index, status) in [AVAssetWriter.Status.writing, .failed, .failed].enumerated() {
                AVAssetWriter.nextInitialStatus = .unknown
                AVAssetWriter.nextFinalStatus = .completed
                try await recorder.startRecording(
                    root.appendingPathComponent("failure-\(mediaType.rawValue)-\(index).mp4"),
                    settings: [mediaType: StreamRecorder.defaultSettings[mediaType]!]
                )
                let errors = await recorder.error
                let sampleType: CMFormatDescription.MediaType = mediaType == .video ? .video : .audio
                await recorder.append(CMSampleBuffer(sampleType, seconds: 0))
                let writer = AVAssetWriter.latest!
                precondition(writer.status == .writing)
                precondition(writer.inputs.count == 1)
                writer.inputs[0].isReadyForMoreMediaData = false
                writer.status = status
                let appendCount = AVAssetWriterInput.appendCount
                for timestamp in 1...4 {
                    await recorder.append(CMSampleBuffer(sampleType, seconds: Double(timestamp)))
                }
                precondition(AVAssetWriterInput.appendCount == appendCount, "busy input must not append")
                // Close this error stream before stopRecording, so stop cannot supply the event.
                _ = await recorder.error
                var errorCount = 0
                for await error in errors {
                    guard case .failedToAppend(let underlying) = error else {
                        preconditionFailure("unexpected recorder error: \(error)")
                    }
                    precondition((underlying as NSError?)?.domain == "FixtureWriter")
                    precondition((underlying as NSError?)?.code == 1)
                    errorCount += 1
                }
                let expected = status == .failed ? 1 : 0
                let matches = errorCount == expected
                if !matches { failures += 1 }
                print("\(mediaType.rawValue) \(status) input-not-ready: errors=\(errorCount) expected=\(expected) \(matches ? "PASS" : "FAIL")")
                do {
                    _ = try await recorder.stopRecording()
                    precondition(status == .writing)
                } catch StreamRecorder.Error.failedToFinishWriting {
                    precondition(status == .failed)
                }
            }
        }
        return failures
    }

    private static func append(
        _ type: CMFormatDescription.MediaType,
        seconds: Double,
        to recorder: StreamRecorder
    ) async {
        let expected = AVAssetWriterInput.appendCount + 1
        recorder.mixer(MediaMixer(), didOutput: CMSampleBuffer(type, seconds: seconds))
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while AVAssetWriterInput.appendCount < expected && ProcessInfo.processInfo.systemUptime < deadline {
            await Task.yield()
        }
        precondition(AVAssetWriterInput.appendCount == expected, "fixture append did not run")
        _ = await recorder.outputURL
    }
}
