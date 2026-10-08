import AVFoundation
import Flutter
import UIKit

public final class BibleitdaAppleSpeechPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var activeSession: WhisperSpeechSession?
  private var whisperEngine: WhisperEngine?
  private var engineLoadTask: Task<WhisperEngine, Error>?

  public static func register(with registrar: FlutterPluginRegistrar) {
    WhisperModelStore.removeLegacyModelsAtStartup()
    let instance = BibleitdaAppleSpeechPlugin()
    let methodChannel = FlutterMethodChannel(
      name: "bibleitda_apple_speech/methods",
      binaryMessenger: registrar.messenger()
    )
    let eventChannel = FlutterEventChannel(
      name: "bibleitda_apple_speech/events",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    eventChannel.setStreamHandler(instance)
    instance.preloadCachedEngine()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availability":
      result([
        "supported": ProcessInfo.processInfo.isOperatingSystemAtLeast(
          OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        ),
        "systemVersion": UIDevice.current.systemVersion,
        "minimumVersion": "14.0",
      ])
    case "start":
      let arguments = call.arguments as? [String: Any]
      let localeIdentifier = arguments?["localeIdentifier"] as? String ?? "ko_KR"
      let contextualPhrases = arguments?["contextualPhrases"] as? [String] ?? []
      Task { @MainActor [weak self] in
        guard let self else {
          result("listen_error")
          return
        }
        guard await Self.requestMicrophonePermission() else {
          result("permission_denied")
          return
        }

        await self.activeSession?.cancel()
        self.activeSession = nil

        do {
          let engine = try await self.loadEngine()
          let session = WhisperSpeechSession(engine: engine) { [weak self] event in
            self?.emit(event)
          }
          self.activeSession = session
          try session.start(localeIdentifier: localeIdentifier, contextualPhrases: contextualPhrases)
          result("started:whisper_cpp_tiny")
        } catch {
          self.activeSession = nil
          self.emit([
            "type": "error",
            "code": "listen_error",
            "message": error.localizedDescription,
          ])
          result("listen_error")
        }
      }
    case "stop":
      Task { @MainActor [weak self] in
        guard let self, let session = self.activeSession else {
          result(nil)
          return
        }
        await session.stop()
        self.activeSession = nil
        result(nil)
      }
    case "cancel":
      Task { @MainActor [weak self] in
        guard let self, let session = self.activeSession else {
          result(nil)
          return
        }
        await session.cancel()
        self.activeSession = nil
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func loadEngine() async throws -> WhisperEngine {
    if let whisperEngine {
      return whisperEngine
    }
    if let engineLoadTask {
      return try await engineLoadTask.value
    }

    emit(["type": "status", "status": "preparing_model", "engine": "whisper_cpp_tiny"])
    let startedAt = Date()
    let task = Task<WhisperEngine, Error> { [weak self] in
      let modelURL = try await WhisperModelStore.lightModelURL(
        diagnostic: { message in
          self?.emit(["type": "diagnostic", "message": message])
        },
        progress: { receivedBytes, totalBytes in
          let fraction = totalBytes > 0
            ? min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
            : 0
          self?.emit([
            "type": "download",
            "status": "downloading",
            "model": "tiny",
            "progress": fraction,
            "receivedBytes": receivedBytes,
            "totalBytes": totalBytes,
          ])
        }
      )
      return try await WhisperEngine.load(modelURL: modelURL)
    }
    engineLoadTask = task
    do {
      let engine = try await task.value
      whisperEngine = engine
      engineLoadTask = nil
      emit([
        "type": "diagnostic",
        "message": "whisper_model_ready:tiny:77691713:elapsed_ms=\(Self.elapsedMilliseconds(since: startedAt))",
      ])
      return engine
    } catch {
      engineLoadTask = nil
      throw error
    }
  }

  private func preloadCachedEngine() {
    guard whisperEngine == nil,
          engineLoadTask == nil,
          let modelURL = WhisperModelStore.cachedLightModelURL() else {
      return
    }

    let startedAt = Date()
    let task = Task<WhisperEngine, Error> {
      try await WhisperEngine.load(modelURL: modelURL)
    }
    engineLoadTask = task
    Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let engine = try await task.value
        if self.whisperEngine == nil {
          self.whisperEngine = engine
        }
        self.engineLoadTask = nil
        self.emit([
          "type": "diagnostic",
          "message": "whisper_model_preloaded:tiny:elapsed_ms=\(Self.elapsedMilliseconds(since: startedAt))",
        ])
      } catch {
        self.engineLoadTask = nil
        self.emit([
          "type": "diagnostic",
          "message": "whisper_model_preload_failed:\(error.localizedDescription)",
        ])
      }
    }
  }

  private static func elapsedMilliseconds(since startedAt: Date) -> Int {
    Int(Date().timeIntervalSince(startedAt) * 1_000)
  }

  private func emit(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }

  @MainActor
  private static func requestMicrophonePermission() async -> Bool {
    let audioSession = AVAudioSession.sharedInstance()
    switch audioSession.recordPermission {
    case .granted:
      return true
    case .undetermined:
      return await withCheckedContinuation { continuation in
        audioSession.requestRecordPermission { granted in
          continuation.resume(returning: granted)
        }
      }
    default:
      return false
    }
  }
}
