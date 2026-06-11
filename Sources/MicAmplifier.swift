#if os(iOS)
import AVFoundation
import Combine

/// Low-latency microphone-to-headphone amplifier.
///
/// Routes mic input straight to the output via AVAudioEngine with a
/// 256-frame I/O buffer (~5.3 ms @ 48 kHz). Gain is applied with an
/// AVAudioUnitEQ global gain stage (supports amplification above unity,
/// up to +24 dB). Audio is hard-muted whenever no headphones are attached
/// to prevent a mic→speaker feedback loop.
public final class MicAmplifier: ObservableObject {

    // MARK: - Public state

    public enum State: Equatable {
        case stopped
        case running
        case mutedNoHeadphones
        case interrupted
        case failed(String)
    }

    @Published public private(set) var state: State = .stopped

    /// Smoothed input level in dBFS (-120 = silence), updated ~15x/sec.
    @Published public private(set) var inputLevelDB: Float = -120

    /// Gain in decibels. Range: -96 dB (silence) ... +24 dB (max boost).
    public var gainDB: Float {
        get { eq.globalGain }
        set { eq.globalGain = min(max(newValue, -96.0), 24.0) }
    }

    /// Linear gain convenience wrapper (1.0 = unity, 2.0 ≈ +6 dB).
    public var linearGain: Float {
        get { pow(10.0, gainDB / 20.0) }
        set { gainDB = 20.0 * log10(max(newValue, .leastNonzeroMagnitude)) }
    }

    /// Receives a passive copy of every input buffer (e.g. for transcription
    /// or metering). Called on a realtime audio thread — do not block.
    /// Adds no latency to the monitoring path.
    public var audioBufferHandler: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?

    // MARK: - Private

    private let engine = AVAudioEngine()
    private let eq = AVAudioUnitEQ(numberOfBands: 0)   // used only for globalGain
    private let muteMixer = AVAudioMixerNode()          // safety mute stage
    private let session = AVAudioSession.sharedInstance()
    private var observers: [NSObjectProtocol] = []

    private static let targetSampleRate: Double = 48_000
    private static let targetFrames: Double = 256
    private static let targetBufferDuration = targetFrames / targetSampleRate // ~5.3 ms

    public init(initialGainDB: Float = 6.0) {
        eq.globalGain = initialGainDB
        registerNotifications()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        stop()
    }

    // MARK: - Lifecycle

    /// Requests mic permission, configures the session, and starts the engine.
    public func start() {
        switch session.recordPermission {
        case .granted:
            startEngine()
        case .undetermined:
            session.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.startEngine() : self?.fail("Microphone permission denied")
                }
            }
        case .denied:
            fail("Microphone permission denied — enable it in Settings")
        @unknown default:
            fail("Unknown microphone permission state")
        }
    }

    public func stop() {
        engine.stop()
        engine.reset()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        state = .stopped
    }

    // MARK: - Engine setup

    private func startEngine() {
        do {
            try configureSession()
            try buildGraphAndStart()
            applyHeadphoneSafety()
        } catch {
            fail("Engine start failed: \(error.localizedDescription)")
        }
    }

    private func configureSession() throws {
        // .measurement disables system DSP (AGC, EQ, voice processing) for
        // minimum added latency and an unprocessed signal path.
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.allowBluetoothA2DP]
        )
        try session.setPreferredSampleRate(Self.targetSampleRate)
        try session.setPreferredIOBufferDuration(Self.targetBufferDuration)
        try session.setActive(true)
    }

    private func buildGraphAndStart() throws {
        // Tearing down any previous graph keeps restarts (route changes,
        // interruptions) idempotent.
        engine.stop()
        engine.reset()
        if eq.engine == nil { engine.attach(eq) }
        if muteMixer.engine == nil { engine.attach(muteMixer) }

        // Use the hardware input format end-to-end; any format conversion
        // inserts buffering and adds latency.
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(
                domain: "MicAmplifier", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid hardware input format"]
            )
        }

        engine.connect(engine.inputNode, to: eq, format: format)
        engine.connect(eq, to: muteMixer, format: format)
        engine.connect(muteMixer, to: engine.outputNode, format: format)

        // Reinstalled on every rebuild since the format can change per route.
        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, time in
            guard let self else { return }
            self.audioBufferHandler?(buffer, time)
            self.publishInputLevel(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    private var levelBufferCounter = 0

    private func publishInputLevel(_ buffer: AVAudioPCMBuffer) {
        levelBufferCounter += 1
        guard levelBufferCounter % 3 == 0,
              let samples = buffer.floatChannelData?[0],
              buffer.frameLength > 0 else { return }

        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let db = 20 * log10(max(sqrt(sum / Float(count)), 1e-6))
        DispatchQueue.main.async { self.inputLevelDB = db }
    }

    // MARK: - Headphone safety

    private var headphonesConnected: Bool {
        // The simulator never reports headphone route types, even when the
        // Mac is using headphones — and Mac speakers can't feed back into
        // the simulated mic path, so bypassing the check is safe here.
        #if targetEnvironment(simulator)
        return true
        #else
        session.currentRoute.outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio:
                return true
            default:
                return false
            }
        }
        #endif
    }

    /// Mutes output immediately when no headphones are present. Routing the
    /// amplified mic to the built-in speaker would create a feedback loop.
    private func applyHeadphoneSafety() {
        if headphonesConnected {
            muteMixer.outputVolume = 1.0
            if engine.isRunning { state = .running }
        } else {
            muteMixer.outputVolume = 0.0
            state = .mutedNoHeadphones
        }
    }

    // MARK: - Notifications

    private func registerNotifications() {
        let nc = NotificationCenter.default

        observers.append(nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        })

        observers.append(nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        })

        // Media services can be killed and restarted by the OS; the entire
        // engine and session must be rebuilt when that happens.
        observers.append(nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.state != .stopped else { return }
            self.startEngine()
        })
    }

    private func handleRouteChange(_ notification: Notification) {
        guard state != .stopped else { return }

        // Mute *before* restarting the engine so no amplified audio escapes
        // through the speaker during the route transition.
        applyHeadphoneSafety()

        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }

        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable, .override, .wakeFromSleep:
            // Hardware format and buffer size may differ on the new route;
            // rebuild the graph so connections match the new hardware format.
            do {
                try buildGraphAndStart()
                applyHeadphoneSafety()
            } catch {
                fail("Restart after route change failed: \(error.localizedDescription)")
            }
        default:
            break
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch type {
        case .began:
            state = .interrupted
        case .ended:
            let optionsRaw = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if options.contains(.shouldResume), state == .interrupted {
                startEngine()
            }
        @unknown default:
            break
        }
    }

    private func fail(_ message: String) {
        engine.stop()
        state = .failed(message)
    }

    // MARK: - Diagnostics

    /// Actual hardware buffer duration and sample rate granted by the OS.
    /// iOS treats the preferred values as hints; verify what you really got.
    public var currentLatencyInfo: (bufferDuration: TimeInterval, sampleRate: Double, ioLatency: TimeInterval) {
        (
            session.ioBufferDuration,
            session.sampleRate,
            session.inputLatency + session.outputLatency + session.ioBufferDuration
        )
    }
}
#endif
