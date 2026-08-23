# Bibleitda Speech

Flutter plugin used by Bibleitda's Bible-writing STT flow on iOS and Android.

- Captures 16 kHz mono microphone audio and transcribes it locally with
  whisper.cpp multilingual `tiny`.
- Downloads the model once, verifies its SHA-256, and caches it in local app
  storage. The iOS model directory is excluded from backups.
- Does not upload microphone audio to an external STT server.
- Uses the same Flutter event and Bible-text matching contract on both mobile
  platforms.
- Uses Metal and Accelerate on iOS and native Android audio/JNI integration on
  Android.

The shared and platform-specific maintenance boundaries are documented in
[`docs/STT_PLATFORM_MAINTENANCE.md`](docs/STT_PLATFORM_MAINTENANCE.md).

## FlutterFlow dependency

```yaml
bibleitda_apple_speech:
  git:
    url: https://github.com/Newercorp/bibleitda-apple-speech.git
    ref: v0.2.2
```

The host app must include iOS microphone usage text and Android microphone
permission. The first STT start needs network access to download the
77,691,713-byte `ggml-tiny.bin` model. Later starts use the verified local copy.
