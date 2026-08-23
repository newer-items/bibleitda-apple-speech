# Bibleitda Apple Speech

iOS-only Flutter plugin used by Bibleitda's Bible-writing STT flow.

- Captures 16 kHz mono microphone audio and transcribes it with whisper.cpp `base`.
- Downloads the official multilingual model once, verifies its SHA-256, and caches it outside iCloud backup.
- Runs inference fully on the iPhone after the model download; microphone audio is not uploaded.
- Keeps the existing Flutter event contract so Bibleitda's STT matching logic remains unchanged.
- Uses Metal and Accelerate on supported Apple hardware.

Android is intentionally not implemented. Bibleitda continues to use its existing Android `SpeechRecognizer` integration.

## FlutterFlow dependency

```yaml
bibleitda_apple_speech:
  git:
    url: https://github.com/Newercorp/bibleitda-apple-speech.git
    ref: v0.1.0
```

The host app must include `NSMicrophoneUsageDescription` in `Info.plist`. The plugin supports iOS 14 and later. The first start needs network access to download the 147,951,465-byte `ggml-base.bin` model; later starts use the local verified copy.
