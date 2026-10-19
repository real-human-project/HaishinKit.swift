@_exported import Foundation

public struct AVMediaType: Hashable, Sendable {
    public let rawValue: String
    public static let audio = Self(rawValue: "audio")
    public static let video = Self(rawValue: "video")
}
public struct AVFileType: Sendable {
    public static let mp4 = Self()
    public static let mov = Self()
}
public enum AVVideoCodecType { public static let h264 = "h264" }
public let AVFormatIDKey = "format"
public let AVSampleRateKey = "sampleRate"
public let AVNumberOfChannelsKey = "channels"
public let AVVideoCodecKey = "codec"
public let AVVideoHeightKey = "height"
public let AVVideoWidthKey = "width"
public let kAudioFormatMPEG4AAC = 1
public struct CMTime: Sendable {
    public static let zero = Self()
    public init() {}
    public init(seconds: Double, preferredTimescale: Int32) {}
}
public struct CMVideoDimensions: Sendable {
    public let width: Int32
    public let height: Int32
    public init(width: Int32, height: Int32) { self.width = width; self.height = height }
}
public struct AudioStreamBasicDescription {
    public let mSampleRate = 48000.0
    public let mChannelsPerFrame: UInt32 = 1
}
public final class CMFormatDescription {
    public enum MediaType { case audio, video, other }
    public let mediaType: MediaType
    public var audioStreamBasicDescription: AudioStreamBasicDescription? { AudioStreamBasicDescription() }
    public var dimensions: CMVideoDimensions { .init(width: 1920, height: 1080) }
    public init(_ mediaType: MediaType) { self.mediaType = mediaType }
}
public final class CMSampleBuffer: @unchecked Sendable {
    public let formatDescription: CMFormatDescription?
    public var presentationTimeStamp: CMTime { .zero }
    public init(_ mediaType: CMFormatDescription.MediaType) { formatDescription = CMFormatDescription(mediaType) }
}
public class AVAudioBuffer {}
public final class AVAudioTime {}
public final class AVAudioPCMBuffer: AVAudioBuffer {
    public func makeSampleBuffer(_ time: AVAudioTime) -> CMSampleBuffer? { CMSampleBuffer(.audio) }
}
public final class AVAssetWriter: @unchecked Sendable {
    public enum Status: String { case unknown, writing, completed, failed, cancelled }
    nonisolated(unsafe) public static var nextInitialStatus: Status = .unknown
    nonisolated(unsafe) public static var nextFinalStatus: Status = .completed
    public let outputURL: URL
    public var status: Status
    public var error: (any Error)? { status == .failed ? NSError(domain: "FixtureWriter", code: 1) : nil }
    public var inputs: [AVAssetWriterInput] = []
    public var movieFragmentInterval: CMTime = .zero
    private let finalStatus: Status
    public init(outputURL: URL, fileType: AVFileType) throws {
        self.outputURL = outputURL
        status = Self.nextInitialStatus
        finalStatus = Self.nextFinalStatus
    }
    public func finishWriting() async { status = finalStatus }
    public func startWriting() { status = .writing }
    public func startSession(atSourceTime: CMTime) {}
    public func canApply(outputSettings: [String: Any], forMediaType: AVMediaType) -> Bool { true }
    public func add(_ input: AVAssetWriterInput) { inputs.append(input) }
}
public final class AVAssetWriterInput {
    public var expectsMediaDataInRealTime = false
    public var isReadyForMoreMediaData = true
    public init(mediaType: AVMediaType, outputSettings: [String: Any], sourceFormatHint: CMFormatDescription?) {}
    public func markAsFinished() {}
    public func append(_ sampleBuffer: CMSampleBuffer) -> Bool { true }
}
