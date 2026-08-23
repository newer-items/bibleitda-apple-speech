# Bibleitda Apple Speech

iOS-only Flutter plugin used by Bibleitda's Bible-writing STT flow.

- Uses `SpeechTranscriber` on iOS 26 when the requested locale and device are supported.
- Falls back to `DictationTranscriber` on other iOS 26 devices and locales.
- Prefers the built-in microphone and excludes Bluetooth routing during recognition.
- Accepts the current Bible verse as contextual phrases.
- Streams volatile and finalized results, alternatives, lifecycle events, and route diagnostics.

Android is intentionally not implemented. Bibleitda continues to use its existing Android `SpeechRecognizer` integration.

## FlutterFlow dependency

```yaml
bibleitda_apple_speech:
  git:
    url: https://github.com/Newercorp/bibleitda-apple-speech.git
    ref: v0.0.4
```

The host app must include `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` in `Info.plist`. The plugin requires iOS 14 to build and uses the new engine only on iOS 26 or later.
