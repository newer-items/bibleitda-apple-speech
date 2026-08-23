# STT Platform Maintenance

This document is the maintenance contract for Bibleitda writing STT. The main
rule is simple: speech-to-Bible behavior stays shared, while microphone capture
and hardware sensitivity stay platform-specific.

## Architecture

1. The native plugin captures 16 kHz mono audio on each platform.
2. Both platforms run the multilingual whisper.cpp `tiny` model locally.
3. Native results use one Flutter event contract: `status`, `download`,
   `result`, `error`, and `diagnostic`.
4. Flutter `SttManager` merges partial/final results and rejects unanchored
   startup text.
5. FlutterFlow custom functions map recognized speech onto the current Bible
   verse and control forward progress.
6. The mismatch action decides when the temporary red border is shown.

Microphone audio is not sent to the Bibleitda server or an external STT API.

## Shared Management

Change the following for iOS and Android together unless a verified platform
defect requires an exception.

| Area | Current contract | Source of truth |
| --- | --- | --- |
| Model | whisper.cpp multilingual `tiny`, 77,691,713 bytes, SHA-256 verified | `WhisperModelStore` on both platforms |
| Audio format | 16 kHz, mono, normalized floating-point samples | `WhisperSpeechSession` on both platforms |
| First inference | After 16,000 samples, about 1 second | Native sessions |
| Inference interval | 1,000 ms | Native sessions |
| Maximum audio window | 480,000 samples, about 30 seconds | Native sessions |
| Language | Locale language code, with Korean fallback | Native sessions and `SttManager` |
| Startup protection | At least 2 recognized characters and a 2-3 character target anchor | `SttManager.hasReliableNativeAnchor` |
| Bible progress | Minimum 2 matches and 2 contiguous matches | FlutterFlow `matchBibleSTT` |
| Forward limit | Recognized length plus at most 5 Bible characters | FlutterFlow `matchBibleSTT` |
| Error tolerance | Up to 90% recognition error only when the 2-character anchor is present | FlutterFlow `matchBibleSTT` |
| OFF completion | Complete only a verified remaining tail shorter than 5 characters | FlutterFlow `matchBibleSTTResult` |
| Mismatch warning | Starts after 4 accepted characters; flashes after 2 consecutive strong mismatches | `sttFlashMismatchIfNeeded` |
| Session behavior | ON starts a new session; OFF finalizes; next verse stops the old session | `SttManager` and page actions |
| Download UI | Shared FlutterFlow component driven by model download events | `SttModelDownloadState` |

Shared behavior files:

- FlutterFlow custom class: `SttManager`
- FlutterFlow custom functions: `matchBibleSTT`, `matchBibleSTTResult`
- FlutterFlow custom action: `sttFlashMismatchIfNeeded`
- Flutter package event contract under `lib/`

Do not copy matching rules into Swift or Kotlin. Native code should return the
best transcript; Flutter code owns Bible-text correction and display progress.

## Platform-Specific Management

The values below intentionally differ because iOS and Android deliver different
raw microphone levels. Equal numeric thresholds do not mean equal sensitivity.

| Area | iOS | Android |
| --- | --- | --- |
| Capture API | `AVAudioEngine` and `AVAudioSession` | `AudioRecord` |
| Audio mode/source | `.measurement` | `VOICE_RECOGNITION` |
| Processing backend | Metal/Accelerate with CPU fallback | Android native/JNI CPU backend |
| Recent-speech RMS | `0.0015` | `0.003` |
| Required speech frames | `1` x 100 ms | `2` x 100 ms |
| Permission | `NSMicrophoneUsageDescription`, `AVAudioSession.recordPermission` | `RECORD_AUDIO` runtime permission |
| Cached engine preparation | Preload verified cached model in background at plugin registration | Load through Android plugin lifecycle |
| Build integration | CocoaPods, iOS 14 or later | Gradle, CMake and NDK |

Platform files:

- iOS: `ios/Classes/BibleitdaAppleSpeechPlugin.swift`
- iOS: `ios/Classes/WhisperSpeechSession.swift`
- iOS: `ios/Classes/WhisperModelStore.swift`
- Android: `android/.../BibleitdaAppleSpeechPlugin.kt`
- Android: `android/.../WhisperSpeechSession.kt`
- Android: `android/.../WhisperModelStore.kt`

Never make an iOS microphone threshold change in Android merely to keep the
numbers identical. Validate the same user behavior instead: normal speech must
start recognition promptly, silence must not create text, and unrelated startup
phrases must not advance the verse.

## Change Rules

Use a shared change when modifying:

- Bible matching accuracy or allowed progress.
- Duplicate/revision merging.
- ON/OFF, restart, finalization, or next-verse behavior.
- Red mismatch indicator timing and sensitivity.
- Model name, checksum, download state, or Flutter event fields.
- Locale selection and multilingual behavior.

Use a platform-specific change when modifying:

- Microphone API, audio session/category/source, buffer conversion, or route.
- RMS/silence gates and device input sensitivity.
- Metal, Accelerate, JNI, CMake, CocoaPods, Gradle, or permissions.
- Engine warm-up and lifecycle behavior caused by an OS limitation.

If one platform changes native behavior, run regression tests on both platforms
before releasing even when the other source files are unchanged.

## Release Procedure

1. Make plugin changes in `bibleitda_apple_speech`.
2. Update native contract tests in
   `test/bibleitda_apple_speech_test.dart`.
3. Run `flutter test`.
4. Build the iOS example with `flutter build ios --debug --no-codesign`.
5. Build the Android probe APK.
6. Bump the package, podspec, and Gradle versions together.
7. Commit, tag, and push the plugin. Never point FlutterFlow at an untagged
   moving branch.
8. Update the FlutterFlow git dependency to the new tag through FlutterFlow AI.
9. Run `flutterflow ai test` and push to the Development environment.
10. Export fresh generated code and verify `pubspec.lock` resolves the expected
    tag and commit.
11. Test profile/release builds on a physical iPhone and Android device.
12. Promote the same pinned tag to Production only after both pass.

## Physical Test Checklist

- First use shows permission and model-download progress correctly.
- Later app starts do not download the model again.
- The first microphone tap does not look frozen.
- Normal speech begins producing progress within the expected interval.
- Slow speech continues without restarting the sentence.
- A wrong word does not permanently block later correct speech.
- Startup noise such as `고기` or `안녕하세요` does not advance the verse.
- The mismatch border does not flash during ordinary correct speech.
- OFF preserves recognized text and completes only a verified short tail.
- Next verse cannot inherit the previous verse transcript.
- Editing the middle and restarting STT continues from the edited position.
- Korean and at least one non-Korean locale complete the same flow.

## Current Baseline

- Plugin tag: `v0.2.2`
- Plugin commit: `95241a7`
- FlutterFlow Development commit: `Q4dYwrOIuadw4bLNB4zE`
- Verified device: iPhone 13 mini, iOS 26.6.1
- Last verification: 2026-08-23

Update this section whenever the pinned plugin version or verified release
baseline changes.
