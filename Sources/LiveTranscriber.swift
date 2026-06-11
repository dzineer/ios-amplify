#if os(iOS)
import AVFoundation
import Combine
import Speech

/// Streams speech-to-text from live audio buffers.
///
/// Feed it buffers from `MicAmplifier.audioBufferHandler` — the tap is a
/// passive copy, so transcription adds no latency to the monitoring path.
/// Prefers on-device recognition (offline, no duration limits) and falls
/// back to server-based recognition when the locale doesn't support it.
public final class LiveTranscriber: ObservableObject {

    @Published public private(set) var transcript: String = ""
    @Published public private(set) var isTranscribing = false
    @Published public private(set) var errorMessage: String?

    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    public init(locale: Locale = .current) {
        recognizer = SFSpeechRecognizer(locale: locale)
    }

    deinit {
        stop()
    }

    public func start() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition unavailable for this locale"
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self else { return }
                guard status == .authorized else {
                    self.errorMessage = "Speech recognition permission denied"
                    return
                }
                self.beginRecognition(with: recognizer)
            }
        }
    }

    public func stop() {
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isTranscribing = false
    }

    /// Call from the audio tap. Safe to call from the realtime thread —
    /// SFSpeechAudioBufferRecognitionRequest buffers internally.
    public func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }

    private func beginRecognition(with recognizer: SFSpeechRecognizer) {
        stop()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Simulators report on-device support but rarely have the model
        // assets installed, so the task hangs silently — use the server path.
        #if targetEnvironment(simulator)
        request.requiresOnDeviceRecognition = false
        #else
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        #endif
        self.request = request

        errorMessage = nil
        transcript = ""
        isTranscribing = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error, self.isTranscribing {
                    // Cancellation surfaces as an error; only report real failures.
                    let nsError = error as NSError
                    if nsError.code != 301 || nsError.domain != "kLSRErrorDomain" {
                        self.errorMessage = error.localizedDescription
                    }
                    self.isTranscribing = false
                }
            }
        }
    }
}
#endif
