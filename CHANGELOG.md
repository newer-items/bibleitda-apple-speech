## 0.1.0

- Replace Apple SpeechAnalyzer recognition with multilingual whisper.cpp `base` on iOS.
- Keep the existing Flutter STT event API and Android behavior unchanged.
- Add verified first-use model download and persistent on-device model caching.
- Capture and resample microphone audio to 16 kHz mono for rolling partial results.

## 0.0.4

- Prefer Apple's low-latency `SpeechTranscriber` for supported iOS 26 devices.
- Preserve all queued microphone buffers while the on-device model catches up.
- Notify Flutter when the Apple result stream ends so listening can restart.

## 0.0.3

- Reduce live dictation latency and stabilize cumulative transcript revisions.

## 0.0.2

- Prefer Apple's system-dictation transcriber for Bible reading.
- Capture speech with the measurement audio-session mode.

## 0.0.1

* TODO: Describe initial release.
