// Default-mic capture via AVAudioEngine into a Pipeline.
import AVFoundation
import SpeakingSpeedCore

enum CaptureError: Error, CustomStringConvertible {
    case micDenied
    case noInput

    var description: String {
        switch self {
        case .micDenied:
            "Microphone access denied. Allow your terminal app in System Settings → Privacy & Security → Microphone."
        case .noInput:
            "No audio input device."
        }
    }
}

final class Capture {
    private let engine = AVAudioEngine()

    /// Sample rate of the default input; frames are sized from this, no resampling.
    var sampleRate: Double { engine.inputNode.outputFormat(forBus: 0).sampleRate }

    /// Blocks until the user answers the mic prompt (first run only).
    static func requestAccess() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let done = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                granted = ok
                done.signal()
            }
            done.wait()
            if !granted { throw CaptureError.micDenied }
        default:
            throw CaptureError.micDenied
        }
    }

    func start(into pipeline: Pipeline) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw CaptureError.noInput }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            guard let ch = buffer.floatChannelData else { return }
            pipeline.push(Array(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength))))
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
