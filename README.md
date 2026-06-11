# Mic Amplifier

A low-latency iOS microphone amplifier by [Dzineer](https://dzineer.com). Routes live microphone input straight to your headphones with adjustable volume boost and real-time speech transcription — designed with large, accessible controls for users with hearing difficulties.

## Features

- **Low-latency monitoring** — AVAudioEngine passthrough targeting a 256-frame I/O buffer (~5.3 ms @ 48 kHz), with system DSP disabled for the cleanest, fastest path
- **Volume amplification** — gain from -24 dB to +24 dB via an EQ stage (true boost above unity, not just mixer volume)
- **Headphone safety** — output is hard-muted the instant headphones are disconnected, preventing mic-to-speaker feedback loops
- **Live transcription** — on-device speech-to-text streamed from a passive audio tap (zero added latency to the monitoring path)
- **Accessible UI** — oversized slider thumb, large Start/Stop button, and a live mic level indicator
- **Robust audio session handling** — route changes, phone-call interruptions, and media-services resets are all handled

## Requirements

- iOS 17+
- Xcode 16+ (with the iOS platform installed)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A physical iPhone with **wired headphones** for real use — Bluetooth adds 100–200 ms of codec latency, and the simulator can't reproduce device audio routing

## Getting Started

```bash
git clone https://github.com/dzineer/ios-amplify.git
cd ios-amplify/DemoApp
xcodegen generate
open AmplifierDemo.xcodeproj
```

Select your device, set your signing team under Signing & Capabilities, and run.

## Project Layout

| Path | Contents |
|---|---|
| `Sources/MicAmplifier.swift` | Core engine: mic→headphone passthrough, gain, headphone safety, session handling |
| `Sources/LiveTranscriber.swift` | Streaming speech recognition fed by the engine's input tap |
| `DemoApp/` | SwiftUI demo app (generated with XcodeGen from `project.yml`) |
| `Tests/` | Unit tests for gain math and state handling |

## Using the Library

The package can be consumed directly via Swift Package Manager:

```swift
import MicAmplifier

let amplifier = MicAmplifier(initialGainDB: 6.0)
amplifier.start()                      // requests mic permission, starts the engine
amplifier.gainDB = 12.0                // -96...+24 dB
amplifier.audioBufferHandler = { buffer, _ in
    // passive copy of input buffers (metering, transcription, recording)
}
```

`MicAmplifier` is an `ObservableObject` — observe `state` (`running`, `mutedNoHeadphones`, `interrupted`, …) and `inputLevelDB` from SwiftUI.

## Running Tests

```bash
xcodebuild test -scheme MicAmplifier -destination 'platform=iOS Simulator,name=iPhone 17'
```

## License

Copyright © Dzineer. All rights reserved.
