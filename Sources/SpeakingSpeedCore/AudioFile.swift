import AVFoundation

/// First channel of an audio file as Float samples.
public func readMono(_ path: String) throws -> (samples: [Float], sampleRate: Double) {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let format = file.processingFormat
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    let samples = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    return (samples, format.sampleRate)
}
