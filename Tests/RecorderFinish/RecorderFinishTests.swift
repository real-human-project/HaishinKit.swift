import AVFoundation

public protocol StreamOutput {}
public protocol StreamConvertible {}
public protocol MediaMixerOutput {}
public final class MediaMixer {}

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
        print("actual-source recorder contract failures: \(failures)")
        if failures > 0 { exit(1) }
    }
}
