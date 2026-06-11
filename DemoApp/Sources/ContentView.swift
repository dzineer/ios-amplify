import SwiftUI
import MicAmplifier

struct ContentView: View {
    @StateObject private var amplifier = MicAmplifier(initialGainDB: 6.0)
    @StateObject private var transcriber = LiveTranscriber()
    @State private var gainDB: Float = 6.0
    @State private var isRunning = false
    @State private var transcribe = false
    @State private var latencyText = "—"

    private let latencyTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(.systemGray5))
                            Capsule()
                                .fill(levelFraction > 0.05 ? Color.green : Color(.systemGray3))
                                .frame(width: geo.size.width * levelFraction)
                        }
                    }
                    .frame(height: 3)
                    .listRowSeparator(.hidden)
                    Button(isRunning ? "Stop" : "Start") {
                        if isRunning {
                            amplifier.stop()
                        } else {
                            amplifier.start()
                        }
                        isRunning.toggle()
                    }
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity)
                    .tint(isRunning ? .red : .green)
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                } header: {
                    HStack {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 12, height: 12)
                        Text(stateLabel)
                            .font(.headline)
                            .textCase(nil)
                        Spacer()
                        Text(latencyText)
                            .font(.caption2)
                            .textCase(nil)
                    }
                }

                Section {
                    Toggle("Live transcription", isOn: $transcribe)
                        .onChange(of: transcribe) { _, on in
                            if on {
                                amplifier.audioBufferHandler = { [weak transcriber] buffer, _ in
                                    transcriber?.append(buffer)
                                }
                                transcriber.start()
                            } else {
                                amplifier.audioBufferHandler = nil
                                transcriber.stop()
                            }
                        }
                    if let error = transcriber.errorMessage {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                    if transcribe {
                        ScrollViewReader { proxy in
                            ScrollView {
                                Text(transcriber.transcript.isEmpty ? "Listening…" : transcriber.transcript)
                                    .font(.body)
                                    .foregroundStyle(transcriber.transcript.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .topLeading)
                                    .id("transcript")
                            }
                            .frame(height: 110)
                            .onChange(of: transcriber.transcript) { _, _ in
                                proxy.scrollTo("transcript", anchor: .bottom)
                            }
                        }
                    }
                } header: {
                    Text("Transcription")
                }

                Section {
                    BigThumbSlider(value: $gainDB, range: -24...24)
                        .onChange(of: gainDB) { _, newValue in
                            amplifier.gainDB = newValue
                        }
                    HStack {
                        Text("Quieter").font(.title3)
                        Spacer()
                        Text(String(format: "%+.1f dB", gainDB))
                            .font(.title3.monospacedDigit().bold())
                        Spacer()
                        Text("Louder").font(.title3)
                    }
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Volume")
                } footer: {
                    Text("Wired headphones required. Output is muted automatically when headphones are disconnected to prevent feedback.")
                }
            }
            .navigationTitle("Mic Amplifier")
            .onReceive(latencyTimer) { _ in
                guard isRunning else { return }
                let info = amplifier.currentLatencyInfo
                latencyText = String(
                    format: "%.1f ms buffer / %.1f ms total @ %.0f Hz",
                    info.bufferDuration * 1000,
                    info.ioLatency * 1000,
                    info.sampleRate
                )
            }
        }
    }

    private var levelFraction: Double {
        Double(min(max((amplifier.inputLevelDB + 60) / 60, 0), 1))
    }

    private var stateLabel: String {
        switch amplifier.state {
        case .stopped: return "Stopped"
        case .running: return "Running"
        case .mutedNoHeadphones: return "Muted — no headphones"
        case .interrupted: return "Interrupted"
        case .failed(let message): return "Failed: \(message)"
        }
    }

    private var stateColor: Color {
        switch amplifier.state {
        case .stopped: return .gray
        case .running: return .green
        case .mutedNoHeadphones: return .orange
        case .interrupted: return .yellow
        case .failed: return .red
        }
    }
}

#Preview {
    ContentView()
}
