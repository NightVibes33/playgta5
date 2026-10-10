import Foundation
import AVFoundation

/// Thread-safe output adapter for future native engine PCM audio callbacks.
/// This accepts actual float PCM samples without web audio or remote streaming.
/// It cannot produce GTA music/voices before the real engine provides frames.
final class NativePCMOutput {
    static let shared = NativePCMOutput()

    enum AudioError: LocalizedError {
        case invalidFrameCount
        case unavailable
        var errorDescription: String? {
            switch self {
            case .invalidFrameCount: return "Invalid float PCM packet"
            case .unavailable: return "Native audio engine unavailable"
            }
        }
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let queue = DispatchQueue(label: "gtaios.audio.frames")
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000,
                                     channels: 2)!
    private var active = false
    private var queuedBuffers = 0

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result: Result<Void, Error>
            do {
                if !self.active {
                    try AVAudioSession.sharedInstance().setCategory(.playback,
                        mode: .default, options: [.mixWithOthers])
                    try AVAudioSession.sharedInstance().setActive(true)
                    try self.engine.start()
                    self.player.volume = Float(GTALaunchPreferences.fraction("masterVolume", fallback: 1.0))
                    self.player.play()
                    self.active = true
                }
                result = .success(())
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Up to 4096 interleaved stereo frames per packet. This maps to a real
    /// native audio render graph, not to a placeholder audible test tone.
    func scheduleStereoFloatPCM(_ samples: [Float],
                                completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result: Result<Void, Error>
            do {
                let count = samples.count / 2
                guard !samples.isEmpty, samples.count % 2 == 0, count <= 4096 else {
                    throw AudioError.invalidFrameCount
                }
                guard self.active, let buffer = AVAudioPCMBuffer(pcmFormat: self.format,
                    frameCapacity: AVAudioFrameCount(count)),
                    let channels = buffer.floatChannelData else {
                    throw AudioError.unavailable
                }
                buffer.frameLength = AVAudioFrameCount(count)
                for frame in 0..<count {
                    channels[0][frame] = samples[frame * 2]
                    channels[1][frame] = samples[frame * 2 + 1]
                }
                self.player.scheduleBuffer(buffer, completionHandler: nil)
                result = .success(())
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func setMasterVolume(_ value: Float) {
        queue.async {
            self.player.volume = min(1, max(0, value))
        }
    }

    func stop() {
        queue.async {
            guard self.active else { return }
            self.player.stop()
            self.engine.stop()
            self.active = false
        }
    }
}
